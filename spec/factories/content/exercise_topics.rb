FactoryGirl.define do
  factory :content_exercise_topic, class: '::Content::ExerciseTopic' do
    exercise
    topic
  end
end
