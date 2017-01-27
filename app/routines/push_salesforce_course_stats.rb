class PushSalesforceCourseStats

  # This code works hard to catch exceptions when pushing stats for courses, because
  # we don't want an issue with one course to kill stats for all remaining courses.
  # When an exception (or other issue) is encountered, we call `error!` which logs
  # the problem for logging and email notification, then stops the processing of
  # the current course via `throw`/`catch` calls (to avoid always remembering to
  # `return` after `error!` and to avoid using exceptions which we catch all of)

  def self.call(allow_error_email:)
    new(allow_error_email: allow_error_email).call
  end

  def initialize(allow_error_email:)
    @allow_error_email = allow_error_email
    @errors = []
    @num_updates = 0
    @num_errors = 0
  end

  def call
    log { "Starting..." }

    applicable_courses.find_each do |course|
      catch(:course_error) do
        call_for_course(course)
      end
    end

    notify_errors

    counts = {
      num_courses: applicable_courses.size,
      num_updates: @num_updates,
      num_errors: @num_errors
    }

    log {
      "Processed #{counts[:num_courses]} course(s); wrote stats for #{counts[:num_updates]} of " +
      "these; #{counts[:num_errors]} course(s) ran into an error."
    }

    counts
  end

  def call_for_course(course)
    begin
      attached_record = courses_to_attached_records[course]
      os_ancillary = attached_record.try(:salesforce_object)

      # If no OSA, try to make one

      if os_ancillary.nil?
        # First figure out which SF Contact the OSA would hang off of

        sf_contact_id = best_sf_contact_id_for_course(course)
        error!(message: "No teacher SF contact", course: course) if sf_contact_id.nil?

        # Next see if there's an appropriate IndividualAdoption; if not, make one.

        book_name = course.offering.salesforce_book_name

        individual_adoption_criteria = {
          contact_id: sf_contact_id,
          book_name: book_name,
          term_year: salesforce_term_year_for_course(course)
        }

        candidate_individual_adoptions = Salesforce::Remote::IndividualAdoption
                                           .where(individual_adoption_criteria)
                                           .to_a

        if candidate_individual_adoptions.size > 1
          error!(message: "Too many IndividualAdoptions matching #{individual_adoption_criteria}",
                 course: course)
        end

        individual_adoption =
          candidate_individual_adoptions.first ||
          begin
            # quickie iso8601 format
            start_date = course.fall? ? "#{course.year}-08-01" : "#{course.year}-01-01"
            sf_contact = Salesforce::Remote::Contact.where(id: sf_contact_id).first

            Salesforce::Remote::IndividualAdoption.new(
              contact_id: sf_contact_id,
              class_start_date: start_date,
              book_id: book_names_to_sf_ids[book_name],
              school_id: sf_contact.school_id
            ).tap do |ia|
              if !ia.save
                error!(message: "Could not save new IndividualAdoption for inputs " \
                                "#{individual_adoption_criteria}; errors: " \
                                "#{ia.errors.full_messages.join(', ')}",
                       course: course)
              end
            end
          end

        # Now see if there's an appropriate OSA on the IA; if not, make one.
        # Attach the OSA to the course so we can just use it next time.

        os_ancillary_criteria = {
          individual_adoption_id: individual_adoption.id,
          product: course.is_concept_coach ? "Concept Coach" : "Tutor"
        }

        candidate_os_ancillaries = Salesforce::Remote::OsAncillary.where(os_ancillary_criteria).to_a

        if candidate_os_ancillaries.size > 1
          error!(message: "Too many OsAncillaries matching #{os_ancillary_criteria}", course: course)
        end

        os_ancillary = candidate_os_ancillaries.first ||
          begin
            Salesforce::Remote::OsAncillary.new(os_ancillary_criteria).tap do |osa|
              if !osa.save
                error!(message: "Could not save new OsAncillary for inputs #{os_ancillary_criteria}; " \
                                "errors: #{osa.errors.full_messages.join(', ')}",
                       course: course)
              end

              # Values in the OSA that are derived from other places in SF, e.g. `TermYear`,
              # cannot be set when creating the record.  Instead of manually setting them
              # here, just reload the object from SF so that we know any derived fields are
              # populated.
              osa.reload
            end
          end

        Salesforce::AttachRecord[record: os_ancillary, to: course]
      end

      push_stats(course, os_ancillary)

    rescue Exception => ee
      error!(exception: ee, course: course)
    end
  end

  def salesforce_term_year_for_course(course)
    start_year = course.spring? ? course.year - 1 : course.year
    Salesforce::Remote::TermYear.new(start_year: start_year, term: course.term.to_sym).to_s
  end

  def push_stats(course, os_ancillary)
    error!(message: 'OS Ancillary nil in `push_stats`', course: course) if os_ancillary.nil?

    os_ancillary.error = nil

    begin
      periods = course.periods

      os_ancillary.course_id = course.id
      os_ancillary.created_at = course.created_at.iso8601
      os_ancillary.teacher_join_url = UrlGenerator.teach_course_url(course.teach_token)

      os_ancillary.num_teachers = course.teachers.length
      os_ancillary.num_students = periods.flat_map(&:latest_enrollments_with_deleted).length
      os_ancillary.num_sections = periods.length

      os_ancillary.status = Salesforce::Remote::OsAncillary::STATUS_APPROVED
      os_ancillary.product = course.is_concept_coach ? "Concept Coach" : "Tutor"
    rescue Exception => ee
      os_ancillary.error = "Unable to update stats: #{ee.message}"
      error!(message: 'Unable to update stats', exception: ee, course: course)
    end

    begin
      return if !os_ancillary.changed?

      if os_ancillary.save
        @num_updates += 1
      else
        error!(message: os_ancillary.errors.full_messages.join(', '), course: course)
      end
    rescue Exception => ee
      error!(message: 'OSA save error', exception: ee, course: course)
    end
  end

  def best_sf_contact_id_for_course(course)
    course.teachers
          .order(:created_at)
          .map{|tt| tt.role.role_user.profile.account.salesforce_contact_id}
          .compact
          .first
  end

  def applicable_courses
    # Only update courses from this term and any term in the future (looking at future
    # courses will get us going on courses made way in advance of the start date).
    # After July of a year, don't update courses from the preceding spring.
    @courses ||=
      CourseProfile::Models::Course.where{year.gt my{Time.now.year - 1}}.tap do |courses|
        courses.reject!{|cc| cc.year == Time.now.year && cc.spring?} if Time.now.month >= 7
      end
  end

  def courses_to_attached_records
    @courses_to_attached_records ||= begin
      ars = Salesforce::AttachedRecord
              .preload(:salesforce_objects)
              .select{|ar| ar.attached_to_class_name == "CourseProfile::Models::Course"}
      ars.map{|ar| [ar.attached_to, ar]}.to_h
    end
  end

  def book_names_to_sf_ids # TODO move these to SalesforceHelper (subclass that for spec helper stuff)?
    @book_names_to_sf_ids ||= begin
      all_books = Salesforce::Remote::Book.all
      all_books.each_with_object({}) do |book, hash|
        hash[book.name] = book.id
      end
    end
  end

  def school_names_to_sf_ids
    @school_names_to_sf_ids ||= begin
      Salesforce::Remote::School.all.each_with_object({}) do |school, hash|
        hash[school.name] = school.id
      end
    end
  end

  def log(&block)
    Rails.logger.info { "[#{self.class.name}] #{block.call}" }
  end

  def error!(exception: nil, message: nil, course: nil)
    error = {}

    error[:message] = message || exception.try(:message)
    error[:exception] = {
      class: exception.class.name,
      message: exception.message,
      first_backtrace_line: exception.backtrace.try(:first)
    } if exception.present?
    error[:course] = course.id if course.present?

    @errors.push(error)

    @num_errors += 1

    throw :course_error
  end

  def notify_errors
    return if @errors.empty?

    Rails.logger.warn { "[#{self.class.name}] Errors: " + @errors.inspect }

    if @allow_error_email && is_real_production?
      DevMailer.inspect_object(
        object: @errors,
        subject: "#{self.class.name} errors",
        to: Rails.application.secrets.salesforce['mail_recipients']
      ).deliver_later
    end
  end

  def is_real_production?
    Rails.application.secrets.environment_name == "prodtutor"
  end

end
