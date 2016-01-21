class Tasks::GetTaskPlans

  COMPLETED_TASK_STEPS = Squeel::Nodes::Literal.new 'CASE WHEN tasks_task_steps.first_completed_at IS NULL THEN 0 ELSE 1 END'
  CORRECT_TASKED_EXERCISES = Squeel::Nodes::Literal.new 'CASE WHEN tasks_tasked_exercises.correct_answer_id = tasks_tasked_exercises.answer_id THEN 1 ELSE 0 END'

  lev_routine express_output: :plans

  protected

  def exec(owner:, include_trouble_flags: false)
    outputs[:plans] = Tasks::Models::TaskPlan.where(owner: owner)
    return unless include_trouble_flags

    outputs[:trouble_plan_ids] = outputs[:plans]
      .joins(tasks: [:taskings, tasked_exercises: :exercise])
      .group([
        :id,
        {tasks: {taskings: :course_membership_period_id}},
        {tasks: {tasked_exercises: {exercise: :content_page_id}}}
      ]).having{
        (sum(COMPLETED_TASK_STEPS) > count(tasks.tasked_exercises.id)/4) & \
        (sum(CORRECT_TASKED_EXERCISES) < sum(COMPLETED_TASK_STEPS)/2)
      }.distinct.pluck(:id)
  end

end