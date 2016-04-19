class TaskExercise

  lev_routine

  protected

  def exec(exercise:, title: nil, task: nil, task_step: nil)

    # This routine will make one step per exercise part.  If provided, the
    # incoming `task_step` will be used as the first step.

    task ||= task_step.try(:task)
    fatal_error(code: :cannot_get_task) if task.nil?

    questions = exercise.content_as_independent_questions

    outputs[:task_steps] = questions.each_with_index.map do |question, ii|

      # Make sure that all steps after the first exercise part get their own new step
      task_step = nil if ii > 0
      task_step ||= Tasks::Models::TaskStep.new

      task_step.tasked = Tasks::Models::TaskedExercise.new(
        content_exercise_id: exercise.id,
        url: exercise.url,
        title: title || exercise.title,
        content: question[:content],
        question_id: question[:id],
        is_in_multipart: questions.size > 1
      )

      task.add_step(task_step)

      yield task_step if block_given?

      task_step
    end
  end

end
