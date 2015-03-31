require 'rails_helper'

RSpec.describe RecoverTaskedExercise, :type => :routine do

  let!(:lo)              { FactoryGirl.create :content_tag,
                                              name: 'ost-tag-lo-test-lo01' }
  let!(:tasked_reading)  { FactoryGirl.create(:tasks_tasked_reading) }
  let!(:tasked_exercise) { FactoryGirl.create(:tasks_tasked_exercise) }
  let!(:tasked_exercise_with_recovery) { FactoryGirl.create(
    :tasks_tasked_exercise,
    has_recovery: true,
    content: OpenStax::Exercises::V1.fake_client
                                    .new_exercise_hash(tags: [lo.name]).to_json
  ) }
  let!(:recovery_exercise) { FactoryGirl.create(
    :content_exercise,
    content: OpenStax::Exercises::V1.fake_client
                                    .new_exercise_hash(tags: [lo.name]).to_json
  ) }
  let!(:recovery_tagging)   { FactoryGirl.create(
    :content_exercise_tag, exercise: recovery_exercise, tag: lo
  ) }

  it "cannot be called on taskeds without a recovery step" do
    result = nil
    expect {
      result = RecoverTaskedExercise.call(tasked_exercise: tasked_reading)
    }.not_to change{ tasked_reading.task_step }
    expect(result.errors.first.code).to eq(:recovery_not_available)

    result = nil
    expect {
      result = RecoverTaskedExercise.call(tasked_exercise: tasked_exercise)
    }.not_to change{ tasked_reading.task_step }
    expect(result.errors.first.code).to eq(:recovery_not_available)
  end

  it "adds an extra recovery step after the given step" do
    result = nil
    recovery_step = nil
    task_step = tasked_exercise_with_recovery.task_step
    task = task_step.task
    reading_step = FactoryGirl.create(:task_step, task: task)
    task.task_steps << reading_step
    expect {
      result = RecoverTaskedExercise.call(
        tasked_exercise: tasked_exercise_with_recovery
      )
    }.to change{ recovery_step = task_step.reload.next_by_number }

    expect(result.errors).to be_empty
    recovery_tasked = recovery_step.tasked
    expect(recovery_tasked.url).to eq recovery_exercise.url
    expect(recovery_tasked.title).to eq recovery_exercise.title
    expect(recovery_tasked.content).to eq recovery_exercise.content
    expect(reading_step.reload.number).to eq recovery_step.number + 1
  end

end
