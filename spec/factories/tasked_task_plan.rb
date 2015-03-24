FactoryGirl.define do
  factory :tasked_task_plan, parent: :task_plan do

    transient do
      number_of_students 10
    end

    owner { Domain::CreateCourse.call.outputs.course }

    settings do
      cnx_page  = OpenStax::Cnx::V1::Page.new(
        hash: {'id' => '092bbf0d-0729-42ce-87a6-fd96fd87a083', 'title' => 'Force'}
      )
      book_part = FactoryGirl.create :content_book_part
      page      = Content::ImportPage.call(cnx_page: cnx_page, book_part: book_part).outputs.page
      { page_ids: [page.id] }
    end

    after(:create) do |task_plan,evaluator|
      taskees = evaluator.number_of_students.times.collect{ FactoryGirl.create :user }
      IReadingAssistant.distribute_tasks(task_plan: task_plan, taskees: taskees)
    end
  end
end
