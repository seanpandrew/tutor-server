class Tasks::Assistants::HomeworkAssistant

  def self.schema
    '{
      "type": "object",
      "required": [
        "exercise_ids",
        "exercises_count_dynamic"
      ],
      "properties": {
        "exercise_ids": {
          "type": "array",
          "items": {
            "type": "integer"
          }
        },
        "exercises_count_dynamic": {
          "type": "integer",
          "minimum": 2,
          "maximum": 4
        },
        "description": {
          "type": "string"
        },
        "page_ids": {
          "type": "array",
          "items": {
            "type": "integer"
          }
        }
      },
      "additionalProperties": false
    }'
  end

  def self.distribute_tasks(task_plan:, taskees:)
    exercises = collect_exercises(task_plan: task_plan)

    tasks = taskees.collect do |taskee|
      task = create_homework_task!(
        task_plan: task_plan,
        taskee:    taskee,
        exercises: exercises
      )
      assign_task!(task: task, taskee: taskee)
      task
    end

    tasks
  end

  def self.collect_exercises(task_plan:)
    exercises = task_plan.settings['exercise_ids'].collect do |exercise_id|
      Content::GetExercise.call(id: exercise_id).outputs.exercise
    end
    exercises
  end

  def self.create_homework_task!(task_plan:, taskee:, exercises:)
    task = create_task!(task_plan: task_plan)
    add_core_steps!(task: task, exercises: exercises)
    add_spaced_practice_exercise_steps!(task: task, taskee: taskee)
  end

  def self.create_task!(task_plan:)
    title    = task_plan.title || 'Homework'
    opens_at = task_plan.opens_at
    due_at   = task_plan.due_at || (task_plan.opens_at + 1.week)

    description = task_plan.settings['description']

    task = Tasks::CreateTask[
      task_plan:   task_plan,
      task_type:   'homework',
      title:       title,
      description: description,
      opens_at:    opens_at,
      due_at:      due_at,
      feedback_at: due_at
    ]

    task.save!
    task
  end

  def self.add_core_steps!(task:, exercises:)
    exercises.each do |exercise|
      step = add_exercise_step(task: task, exercise: exercise)
      step.core_group!
    end

    task.save!
    task
  end

  def self.add_exercise_step(task:, exercise:)
    step = Tasks::Models::TaskStep.new(task: task)
    TaskExercise[task_step: step, exercise: exercise]
    task.task_steps << step
    step
  end

  def self.add_spaced_practice_exercise_steps!(task:, taskee:)
    # k_ago_map = [[1, 4]]
    # k_ago_map.each do |k_ago, number|
    #   number.times do
    #     hash = OpenStax::Exercises::V1.fake_client.new_exercise_hash
    #     exercise = OpenStax::Exercises::V1::Exercise.new(hash.to_json)
    #     step = add_exercise_step(task: task, exercise: exercise)
    #     step.spaced_practice_group!
    #   end
    # end

    homework_history = get_taskee_homework_history(task: task, taskee: taskee)
    #puts "taskee: #{taskee.inspect}"
    #puts "ireading history:  #{homework_history.inspect}"

    exercise_history = get_exercise_history(tasks: homework_history)
    #puts "exercise history:  #{exercise_history.collect{|ex| ex.id}.sort}"

    exercise_pools = get_exercise_pools(tasks: homework_history)
    #puts "exercise pools:  #{exercise_pools.map{|ep| ep.collect{|ex| ex.id}.sort}}}"

    self.k_ago_map.each do |k_ago, number|
      break if k_ago >= exercise_pools.count

      candidate_exercises = (exercise_pools[k_ago] - exercise_history).sort_by{|ex| ex.id}.take(10)

      number.times do
        #puts "candidate_exercises: #{candidate_exercises.collect{|ex| ex.id}.sort}"
        #puts "exercise history:    #{exercise_history.collect{|ex| ex.id}.sort}"

        chosen_exercise = candidate_exercises.first #sample
        #puts "chosen exercise:     #{chosen_exercise.id}"

        candidate_exercises.delete(chosen_exercise)
        exercise_history.push(chosen_exercise)

        step = add_exercise_step(task: task, exercise: chosen_exercise)
        step.spaced_practice_group!
      end
    end

    task.save!
    task
  end

  def self.get_taskee_homework_history(task:, taskee:)
    tasks = Tasks::Models::Task.joins{taskings}.
                                where{taskings.entity_role_id == taskee.id}

    homework_history = tasks.
                         select{|tt| tt.homework?}.
                         reject{|tt| tt == task}.
                         sort_by{|tt| tt.due_at}.
                         push(task).
                         reverse

    homework_history
  end

  def self.get_exercise_history(tasks:)
    exercise_history = tasks.collect do |task|
      exercise_steps = task.task_steps.select{|task_step| task_step.exercise?}
      content_exercises = exercise_steps.collect do |ex_step|
        content_exercise = Content::Models::Exercise.where{url == ex_step.tasked.url}
      end
      content_exercises
    end.flatten.compact
    exercise_history
  end

  def self.get_exercise_pools(tasks:)
    exercise_pools = tasks.collect do |task|
      urls = task.task_steps.select{|task_step| task_step.exercise?}.
                             collect{|task_step| task_step.tasked.url}.
                             uniq

      content_exercises = Content::Models::Exercise.where{url.in urls}

      los = content_exercises.collect do |content_exercise|
        content_exercise.exercise_tags.collect do |ex_tag|
          ex_tag.tag.lo? ? ex_tag.tag.name : nil
        end
      end.flatten.compact.uniq

      exercises = Content::Models::Exercise.joins{exercise_tags.tag}.
                                            where{exercise_tags.tag.name.in los}.
                                            uniq
      exercises = exercises.select do |ex|
        ex.exercise_tags.detect do |ex_tag|
          ['chapter-review-problem', 'chapter-review-concept'].include?(ex_tag.tag.name)
        end
      end

      exercises
    end
    exercise_pools
  end

  def self.k_ago_map
    k_ago_map = [ [0,1], [2,1] ]
  end

  def self.assign_task!(task:, taskee:)
    # No group tasks for this assistant
    task.entity_task.taskings << Tasks::Models::Tasking.new(
      task: task.entity_task,
      role: taskee
    )

    task.save!
    task
  end

end
