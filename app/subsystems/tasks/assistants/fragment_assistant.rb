# An abstract assistant that builds tasks from fragments
class Tasks::Assistants::FragmentAssistant < Tasks::Assistants::GenericAssistant

  protected

  def task_fragments(task:, fragments:, fragment_title:, page:, related_content: nil)
    title = fragment_title

    fragments.each do |fragment|
      step = Tasks::Models::TaskStep.new(task: task)

      case fragment
      when OpenStax::Cnx::V1::Fragment::Exercise
        task_exercise(exercise_fragment: fragment, page: page, step: step, title: title)
      when OpenStax::Cnx::V1::Fragment::OptionalExercise
        # The prompt for the optional exercise appears on the previous step,
        # so that's what is passed in
        previous_step = task.task_steps.last

        store_related_exercises(exercise_fragment: fragment, page: page,
                                previous_step: previous_step, title: title) \
          unless previous_step.nil?
      when OpenStax::Cnx::V1::Fragment::Video
        task_video(video_fragment: fragment, step: step, title: title)
      when OpenStax::Cnx::V1::Fragment::Interactive
        task_interactive(interactive_fragment: fragment, step: step, title: title)
      else
        task_reading(reading_fragment: fragment, page: page, title: title, step: step)
      end

      next if step.tasked.nil?
      step.group_type = :core_group
      step.add_labels(fragment.labels)
      related_content ||= page.related_content
      step.add_related_content(related_content)
      task.task_steps << step

      # The title applies only to the first step in the set of fragments given
      title = nil
    end
  end

  def task_reading(reading_fragment:, page:, step:, title: nil)
    Tasks::Models::TaskedReading.new(task_step: step,
                                     url: page.url,
                                     book_location: page.book_location,
                                     title: title,
                                     content: reading_fragment.to_html)
  end

  def task_exercise(exercise_fragment:, page:, step:, title: nil)
    exercise = get_random_unused_exercise_with_tags(exercise_fragment.embed_tags)

    if exercise.nil?
      node_id = exercise_fragment.node_id
      return if node_id.blank?

      feature_tag = "context-cnxfeature:#{page.uuid}:#{node_id}"
      exercise = get_random_unused_exercise_with_tags([feature_tag])

      return if exercise.nil?
    end

    # Assign the exercise
    TaskExercise[exercise: exercise, title: title, task_step: step]
  end

  def store_related_exercises(exercise_fragment:, page:, previous_step:, title: nil)
    pool_exercises = page.reading_context_pool.exercises
    tasked = previous_step.tasked

    related_exercises = \
    if tasked.is_a?(Tasks::Models::TaskedExercise) # Try Another
      # Retrieve an exercise related to the previous step by LO
      exercise = tasked.exercise

      los = Set.new(exercise.los)
      aplos = Set.new(exercise.aplos)

      pool_exercises.select do |ex|
        ex.los.any?{ |tag| los.include?(tag) } || ex.aplos.any?{ |tag| aplos.include?(tag) }
      end
    else # Try One (Exemplar)
      # Retrieve an exercise tagged with the context-cnxfeature tag
      node_id = exercise_fragment.node_id
      return if node_id.blank?

      feature_tag = "context-cnxfeature:#{page.uuid}:#{node_id}"
      pool_exercises.select{ |ex| ex.tags.any?{ |tag| tag == feature_tag } }
    end

    previous_step.related_exercise_ids = related_exercises.map(&:id) || []
  end

  def task_video(video_fragment:, step:, title: nil)
    Tasks::Models::TaskedVideo.new(task_step: step,
                                   url: video_fragment.url,
                                   title: title,
                                   content: video_fragment.to_html)
  end

  def task_interactive(interactive_fragment:, step:, title: nil)
    Tasks::Models::TaskedInteractive.new(task_step: step,
                                         url: interactive_fragment.url,
                                         title: title,
                                         content: interactive_fragment.to_html)
  end

end
