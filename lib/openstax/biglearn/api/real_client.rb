# Requests that get this far biglearn-api
# or else they will introduce gaps in the sequence_number
# If aborting a request in here is required in the future,
# we will need to introduce a NO-OP CourseEvent in biglearn-api
class OpenStax::Biglearn::Api::RealClient < OpenStax::Biglearn::Api::Client

  HEADER_OPTIONS = { 'Content-Type' => 'application/json' }.freeze

  def initialize(biglearn_configuration)
    @server_url   = biglearn_configuration.server_url
    @token        = biglearn_configuration.token
    @client_id    = biglearn_configuration.client_id
    @secret       = biglearn_configuration.secret

    @oauth_client = OAuth2::Client.new @client_id, @secret, site: @server_url

    @oauth_token  = @oauth_client.client_credentials.get_token unless @client_id.nil?
  end

  def name
    :real
  end

  #
  # API methods
  #

  # ecosystem is a Content::Ecosystem or Content::Models::Ecosystem
  # course is a CourseProfile::Models::Course
  # task is a Tasks::Models::Task
  # student is a CourseMembership::Models::Student
  # book_container is a Content::Chapter or Content::Page or one of their models
  # exercise_id is a String containing an Exercise uuid, number or uid
  # period is a CourseMembership::Period or CourseMembership::Models::Period
  # max_num_exercises is an integer

  # Adds the given ecosystem to Biglearn
  def create_ecosystem(request)
    ecosystem = request.fetch(:ecosystem)
    # Assumes ecosystems only have 1 book
    book = ecosystem.books.preload(
      chapters: [
        :all_exercises_pool,
        {
          pages: [
            :all_exercises_pool, :reading_dynamic_pool, :homework_dynamic_pool, :concept_coach_pool
          ]
        }
      ]
    ).first
    all_pools = book.chapters.flat_map do |chapter|
      [chapter.all_exercises_pool] + chapter.pages.flat_map do |page|
        [
          page.all_exercises_pool,
          page.reading_dynamic_pool,
          page.homework_dynamic_pool,
          page.practice_widget_pool,
          page.concept_coach_pool
        ]
      end
    end
    all_exercise_ids = all_pools.flat_map(&:content_exercise_ids)
    exercise_uuids_by_id = Content::Models::Exercise.where(id: all_exercise_ids)
                                                    .pluck(:id, :uuid)
                                                    .to_h
    exercise_uuids_by_pool = {}
    all_pools.each do |pool|
      exercise_uuids_by_pool[pool] = pool.content_exercise_ids.map do |exercise_id|
        exercise_uuids_by_id[exercise_id]
      end
    end

    contents = [
      {
        container_uuid: book.tutor_uuid,
        container_parent_uuid: ecosystem.tutor_uuid,
        container_cnx_identity: book.cnx_id,
        pools: []
      }
    ]
    book.chapters.each do |chapter|
      pools = [
        {
          use_for_clue: true,
          use_for_personalized_for_assignment_types: [],
          exercise_uuids: exercise_uuids_by_pool[chapter.all_exercises_pool]
        }
      ]

      contents << {
        container_uuid: chapter.tutor_uuid,
        container_parent_uuid: book.tutor_uuid,
        container_cnx_identity: chapter.tutor_uuid,
        pools: pools
      }

      chapter.pages.each do |page|
        pools = [
          {
            use_for_clue: true,
            use_for_personalized_for_assignment_types: [],
            exercise_uuids: exercise_uuids_by_pool[page.all_exercises_pool]
          },
          {
            use_for_clue: false,
            use_for_personalized_for_assignment_types: ['reading'],
            exercise_uuids: exercise_uuids_by_pool[page.reading_dynamic_pool]
          },
          {
            use_for_clue: false,
            use_for_personalized_for_assignment_types: ['homework'],
            exercise_uuids: exercise_uuids_by_pool[page.homework_dynamic_pool]
          },
          {
            use_for_clue: false,
            use_for_personalized_for_assignment_types: ['practice'],
            exercise_uuids: exercise_uuids_by_pool[page.practice_widget_pool]
          },
          {
            use_for_clue: false,
            use_for_personalized_for_assignment_types: ['concept-coach'],
            exercise_uuids: exercise_uuids_by_pool[page.concept_coach_pool]
          }
        ]

        contents << {
          container_uuid: page.tutor_uuid,
          container_parent_uuid: chapter.tutor_uuid,
          container_cnx_identity: page.cnx_id,
          pools: pools
        }
      end
    end

    exercises = ecosystem.exercises.preload(:tags, :page).map do |exercise|
      los = ([ "cnxmod:#{exercise.page.uuid}" ] + exercise.los.map(&:value)).uniq

      {
        exercise_uuid: exercise.uuid,
        group_uuid: exercise.group_uuid,
        version: exercise.version,
        los: los
      }
    end

    biglearn_request = {
      ecosystem_uuid: ecosystem.tutor_uuid,
      book: { cnx_identity: book.cnx_id, contents: contents },
      exercises: exercises,
      imported_at: ecosystem.created_at.utc.iso8601(6)
    }

    single_api_request url: :create_ecosystem, request: biglearn_request
  end

  # Adds the given course to Biglearn
  def create_course(request)
    course = request.fetch(:course)

    biglearn_request = {
      course_uuid: course.uuid,
      ecosystem_uuid: request.fetch(:ecosystem).tutor_uuid,
      is_real_course: !course.is_preview && !course.is_test,
      starts_at: course.starts_at.utc.iso8601(6),
      ends_at: course.ends_at.utc.iso8601(6),
      created_at: course.created_at.utc.iso8601(6)
    }

    single_api_request url: :create_course, request: biglearn_request
  end

  # Prepares Biglearn for a course ecosystem update
  def prepare_course_ecosystem(request)
    course = request.fetch(:course)
    to_ecosystem_model = request.fetch(:ecosystem)
    to_ecosystem = Content::Ecosystem.new strategy: to_ecosystem_model.wrap
    to_course_ecosystems, other_course_ecosystems = course.course_ecosystems
                                                          .partition do |course_ecosystem|
      course_ecosystem.content_ecosystem_id == to_ecosystem.id
    end
    from_ecosystem_model = other_course_ecosystems.first.ecosystem
    from_ecosystem = Content::Ecosystem.new strategy: from_ecosystem_model.wrap
    content_map = Content::Map.find_or_create_by(
      from_ecosystems: [from_ecosystem], to_ecosystem: to_ecosystem
    )
    book_container_mappings = content_map.map_pages_to_pages(pages: from_ecosystem.pages)
                                         .map do |from_page, to_page|
      next if to_page.nil?

      { from_book_container_uuid: from_page.tutor_uuid, to_book_container_uuid: to_page.tutor_uuid }
    end.compact
    exercise_mappings = content_map.map_exercises_to_pages(exercises: from_ecosystem.exercises)
                                   .map do |exercise, page|
      next if page.nil?

      { from_exercise_uuid: exercise.uuid, to_book_container_uuid: page.tutor_uuid }
    end.compact
    prepared_at = request[:prepared_at] ||
                  to_course_ecosystems.first.try!(:created_at) ||
                  Time.current

    biglearn_request = {
      preparation_uuid: request.fetch(:preparation_uuid),
      course_uuid: course.uuid,
      sequence_number: request.fetch(:sequence_number),
      next_ecosystem_uuid: to_ecosystem.tutor_uuid,
      ecosystem_map: {
        from_ecosystem_uuid: from_ecosystem.tutor_uuid,
        to_ecosystem_uuid: to_ecosystem.tutor_uuid,
        book_container_mappings: book_container_mappings,
        exercise_mappings: exercise_mappings
      },
      prepared_at: prepared_at.utc.iso8601(6)
    }

    single_api_request url: :prepare_course_ecosystem, request: biglearn_request
  end

  # Finalizes course ecosystem updates in Biglearn,
  # causing it to stop computing CLUes for the old one
  def update_course_ecosystems(requests)
    biglearn_requests = requests.map do |request|
      course = request.fetch(:course)
      updated_at = request[:updated_at] ||
                   course.course_ecosystems.first.try!(:created_at) ||
                   Time.current

      {
        request_uuid: request.fetch(:request_uuid),
        course_uuid: course.uuid,
        sequence_number: request.fetch(:sequence_number),
        preparation_uuid: request.fetch(:preparation_uuid),
        updated_at: updated_at.utc.iso8601(6)
      }
    end

    bulk_api_request url: :update_course_ecosystems, requests: biglearn_requests,
                     requests_key: :update_requests, responses_key: :update_responses
  end

  # Updates Course rosters in Biglearn
  def update_rosters(requests)
    biglearn_requests = requests.map do |request|
      course = request.fetch(:course)
      course_containers = []
      students = course.periods.flat_map do |period|
        course_containers << {
          container_uuid: period.uuid,
          parent_container_uuid: course.uuid,
          created_at: period.created_at.utc.iso8601(6)
        }.tap do |hash|
          hash[:archived_at] = period.archived_at.utc.iso8601(6) if period.archived?
        end

        period.latest_enrollments.map do |enrollment|
          student = enrollment.student

          {
            student_uuid: student.uuid,
            container_uuid: period.uuid,
            enrolled_at: student.created_at.utc.iso8601(6),
            last_course_container_change_at: enrollment.created_at.utc.iso8601(6)
          }.tap do |hash|
            hash[:dropped_at] = student.dropped_at.utc.iso8601(6) if student.dropped?
          end
        end
      end

      {
        request_uuid: request.fetch(:request_uuid),
        course_uuid: course.uuid,
        sequence_number: request.fetch(:sequence_number),
        course_containers: course_containers,
        students: students
      }
    end.compact

    bulk_api_request url: :update_rosters, requests: biglearn_requests,
                     requests_key: :rosters, responses_key: :updated_rosters, max_requests: 100
  end

  # Updates global exercise exclusions for the given course
  def update_globally_excluded_exercises(request)
    course = request.fetch(:course)

    excluded_ids = Settings::Exercises.excluded_ids.split(',').map(&:strip)
    excluded_numbers_and_versions = excluded_ids.map do |number_or_uid|
      number_or_uid.split('@')
    end
    group_numbers, uids = excluded_numbers_and_versions.partition { |ex| ex.second.nil? }

    group_uuids = Content::Models::Exercise.where(number: group_numbers).distinct.pluck(:group_uuid)
    group_exclusions = group_uuids.map { |group_uuid| { exercise_group_uuid: group_uuid } }

    uuids = uids.empty? ? [] : Content::Models::Exercise.where do
      uids.map { |nn, vv| number.eq(nn) & version.eq(vv) }.reduce(:|)
    end.distinct.pluck(:uuid)
    version_exclusions = uuids.map { |uuid| { exercise_uuid: uuid } }

    exclusions = group_exclusions + version_exclusions

    updated_at = Settings::Exercises.excluded_at || Time.current

    biglearn_request = {
      request_uuid: request.fetch(:request_uuid),
      course_uuid: course.uuid,
      sequence_number: request.fetch(:sequence_number),
      exclusions: exclusions,
      updated_at: updated_at.utc.iso8601(6)
    }

    single_api_request url: :update_globally_excluded_exercises, request: biglearn_request
  end

  # Updates exercise exclusions for the given course
  def update_course_excluded_exercises(request)
    course = request.fetch(:course)

    group_numbers = course.excluded_exercises.map(&:exercise_number)
    group_uuids = Content::Models::Exercise.where(number: group_numbers).distinct.pluck(:group_uuid)
    group_exclusions = group_uuids.map { |group_uuid| { exercise_group_uuid: group_uuid } }

    biglearn_request = {
      request_uuid: request.fetch(:request_uuid),
      course_uuid: course.uuid,
      sequence_number: request.fetch(:sequence_number),
      exclusions: group_exclusions,
      updated_at: course.updated_at.utc.iso8601(6)
    }

    single_api_request url: :update_course_excluded_exercises, request: biglearn_request
  end

  # Updates the given course's start/end dates
  def update_course_active_dates(request)
    course = request.fetch(:course)

    biglearn_request = {
      request_uuid: request.fetch(:request_uuid),
      course_uuid: course.uuid,
      sequence_number: request.fetch(:sequence_number),
      starts_at: course.starts_at,
      ends_at: course.ends_at,
      updated_at: course.updated_at.utc.iso8601(6)
    }

    single_api_request url: :update_course_active_dates, request: biglearn_request
  end

  # Creates or updates tasks in Biglearn
  def create_update_assignments(requests)
    task_id_to_core_page_ids_overrides = {}
    tasks_without_core_page_ids_override = []
    requests.each do |request|
      task = request.fetch(:task)

      if request.has_key?(:core_page_ids)
        task_id_to_core_page_ids_overrides[task.id] = request.fetch(:core_page_ids)
      else
        tasks_without_core_page_ids_override << task
      end
    end

    task_id_to_core_page_ids_map = GetTaskCorePageIds[tasks: tasks_without_core_page_ids_override]
                                     .merge(task_id_to_core_page_ids_overrides)
    all_core_page_ids = task_id_to_core_page_ids_map.values.flatten
    page_id_to_page_uuid_map = Content::Models::Page.where(id: all_core_page_ids)
                                                    .pluck(:id, :tutor_uuid)
                                                    .to_h

    biglearn_requests = requests.map do |request|
      task = request.fetch(:task)
      ecosystem = task.ecosystem
      student = task.taskings.first.try!(:role).try!(:student)
      task_type = task.practice? ? 'practice' : task.task_type

      opens_at = task.opens_at
      due_at = task.due_at
      feedback_at = task.feedback_at

      exclusion_info = {}
      exclusion_info[:opens_at] = opens_at.utc.iso8601(6) if opens_at.present?
      exclusion_info[:due_at] = due_at.utc.iso8601(6) if due_at.present?
      exclusion_info[:feedback_at] = feedback_at.utc.iso8601(6) if feedback_at.present?

      core_page_ids = task_id_to_core_page_ids_map[task.id]
      assigned_book_container_uuids = core_page_ids.map do |page_id|
        page_id_to_page_uuid_map[page_id]
      end
      assigned_exercises = task.tasked_exercises
                               .preload(:task_step, :exercise)
                               .map do |tasked_exercise|
        {
          trial_uuid: tasked_exercise.uuid,
          exercise_uuid: tasked_exercise.exercise.uuid,
          is_spe: tasked_exercise.task_step.spaced_practice_group?,
          is_pe: tasked_exercise.task_step.personalized_group?
        }
      end

      # Calculate desired number of SPEs and PEs
      goal_num_tutor_assigned_spes = request[:goal_num_tutor_assigned_spes]
      if goal_num_tutor_assigned_spes.nil?
        sp_steps = task.task_steps.spaced_practice_group
        spe_steps = sp_steps.select { |step| step.exercise? || step.placeholder? }
        goal_num_tutor_assigned_spes = spe_steps.size
      end

      goal_num_tutor_assigned_pes = request[:goal_num_tutor_assigned_pes]
      if goal_num_tutor_assigned_pes.nil?
        p_steps = task.task_steps.personalized_group
        pe_steps = p_steps.select { |step| step.exercise? || step.placeholder? }
        goal_num_tutor_assigned_pes = pe_steps.size
      end

      {
        request_uuid: request.fetch(:request_uuid),
        course_uuid: request.fetch(:course).uuid,
        sequence_number: request.fetch(:sequence_number),
        assignment_uuid: task.uuid,
        is_deleted: task.task_plan.try!(:withdrawn?),
        ecosystem_uuid: ecosystem.tutor_uuid,
        student_uuid: student.uuid,
        assignment_type: task_type,
        exclusion_info: exclusion_info,
        assigned_book_container_uuids: assigned_book_container_uuids,
        goal_num_tutor_assigned_spes: goal_num_tutor_assigned_spes,
        spes_are_assigned: task.spes_are_assigned,
        goal_num_tutor_assigned_pes: goal_num_tutor_assigned_pes,
        pes_are_assigned: task.pes_are_assigned,
        assigned_exercises: assigned_exercises,
        created_at: task.created_at.utc.iso8601(6),
        updated_at: task.updated_at.utc.iso8601(6)
      }
    end

    bulk_api_request url: :create_update_assignments, requests: biglearn_requests,
                     requests_key: :assignments, responses_key: :updated_assignments
  end

  # Records the given student responses
  def record_responses(requests)
    biglearn_requests = requests.map do |request|
      course = request.fetch(:course)
      tasked_exercise = request.fetch(:tasked_exercise)
      task = tasked_exercise.task_step.task

      {
        response_uuid: request.fetch(:response_uuid),
        course_uuid: course.uuid,
        sequence_number: request.fetch(:sequence_number),
        ecosystem_uuid: task.ecosystem.tutor_uuid,
        trial_uuid: tasked_exercise.uuid,
        student_uuid: task.taskings.first.role.student.uuid,
        exercise_uuid: tasked_exercise.exercise.uuid,
        is_correct: tasked_exercise.is_correct?,
        is_real_response: !course.is_preview && !course.is_test,
        responded_at: tasked_exercise.updated_at.utc.iso8601(6)
      }
    end

    bulk_api_request(
      url: :record_responses,
      requests: biglearn_requests,
      requests_key: :responses,
      responses_key: :recorded_response_uuids
    ) do |response|
      { response_uuid: response }
    end
  end

  # Returns a number of recommended personalized exercises for the given tasks
  def fetch_assignment_pes(requests)
    biglearn_requests = requests.map do |request|
      task = request.fetch(:task)
      course = task.taskings.first.role.student.course
      max_num_exercises = request[:max_num_exercises]

      {
        request_uuid: request.fetch(:request_uuid),
        assignment_uuid: task.uuid,
        algorithm_name: course.biglearn_assignment_pes_algorithm_name
      }.tap do |biglearn_request|
        biglearn_request[:max_num_exercises] = max_num_exercises unless max_num_exercises.nil?
      end
    end

    bulk_api_request url: :fetch_assignment_pes, requests: biglearn_requests,
                     requests_key: :pe_requests, responses_key: :pe_responses
  end

  # Returns a number of recommended spaced practice exercises for the given tasks
  def fetch_assignment_spes(requests)
    biglearn_requests = requests.map do |request|
      task = request.fetch(:task)
      course = task.taskings.first.role.student.course
      max_num_exercises = request[:max_num_exercises]

      {
        request_uuid: request.fetch(:request_uuid),
        assignment_uuid: task.uuid,
        algorithm_name: course.biglearn_assignment_spes_algorithm_name
      }.tap do |biglearn_request|
        biglearn_request[:max_num_exercises] = max_num_exercises unless max_num_exercises.nil?
      end
    end

    bulk_api_request url: :fetch_assignment_spes, requests: biglearn_requests,
                     requests_key: :spe_requests, responses_key: :spe_responses
  end

  # Returns a number of recommended personalized exercises for the student's worst topics
  def fetch_practice_worst_areas_exercises(requests)
    biglearn_requests = requests.map do |request|
      student = request.fetch(:student)
      course = student.course
      max_num_exercises = request[:max_num_exercises]

      {
        request_uuid: request.fetch(:request_uuid),
        student_uuid: student.uuid,
        algorithm_name: course.biglearn_practice_worst_areas_algorithm_name
      }.tap do |biglearn_request|
        biglearn_request[:max_num_exercises] = max_num_exercises unless max_num_exercises.nil?
      end
    end

    bulk_api_request url: :fetch_practice_worst_areas_exercises, requests: biglearn_requests,
                     requests_key: :worst_areas_requests, responses_key: :worst_areas_responses
  end

  # Returns the CLUes for the given book containers and students (for students)
  def fetch_student_clues(requests)
    biglearn_requests = requests.map do |request|
      student = request.fetch(:student)
      course = student.course

      {
        request_uuid: request.fetch(:request_uuid),
        student_uuid: student.uuid,
        book_container_uuid: request.fetch(:book_container).tutor_uuid,
        algorithm_name: course.biglearn_student_clues_algorithm_name
      }
    end

    bulk_api_request url: :fetch_student_clues, requests: biglearn_requests,
                     requests_key: :student_clue_requests, responses_key: :student_clue_responses
  end

  # Returns the CLUes for the given book containers and periods (for teachers)
  def fetch_teacher_clues(requests)
    biglearn_requests = requests.map do |request|
      course_container = request.fetch(:course_container)
      course = course_container.course

      {
        request_uuid: request.fetch(:request_uuid),
        course_container_uuid: course_container.uuid,
        book_container_uuid: request.fetch(:book_container).tutor_uuid,
        algorithm_name: course.biglearn_teacher_clues_algorithm_name
      }
    end

    bulk_api_request url: :fetch_teacher_clues, requests: biglearn_requests,
                     requests_key: :teacher_clue_requests, responses_key: :teacher_clue_responses
  end

  protected

  def algorithm_name
    Settings::Biglearn.algorithm_name
  end

  def absolutize_url(url)
    Addressable::URI.join @server_url, url.to_s
  end

  def api_request(method:, url:, body:)
    absolute_uri = absolutize_url(url)

    header_options = { headers: @token.nil? ? HEADER_OPTIONS : HEADER_OPTIONS.merge(
        'Biglearn-Api-Token' => @token
      )
    }
    request_options = body.nil? ? header_options : header_options.merge(body: body.to_json)

    response = (@oauth_token || @oauth_client).request method, absolute_uri, request_options

    JSON.parse(response.body).deep_symbolize_keys
  end

  def single_api_request(method: :post, url:, request:)
    response_hash = api_request method: method, url: url, body: request

    block_given? ? yield(response_hash) : response_hash
  end

  def bulk_api_request(method: :post, url:, requests:,
                       requests_key:, responses_key:, max_requests: 1000)
    max_requests ||= requests.size

    requests.each_slice(max_requests).flat_map do |requests|
      body = { requests_key => requests }

      response_hash = api_request method: method, url: url, body: body

      responses_array = response_hash[responses_key] || []

      responses_array.map { |response| block_given? ? yield(response) : response }
    end
  end

end
