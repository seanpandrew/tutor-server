require 'rails_helper'
require 'database_cleaner'

RSpec.describe OpenStax::Biglearn::Api, type: :external do
  before(:each) { RequestStore.clear! }
  after(:all)   { RequestStore.clear! }

  context 'configuration' do
    it 'can be configured' do
      configuration = OpenStax::Biglearn::Api.configuration
      expect(configuration).to be_a(OpenStax::Biglearn::Api::Configuration)

      OpenStax::Biglearn::Api.configure do |config|
        expect(config).to eq configuration
      end
    end
  end

  context 'api calls' do
    before(:all) do
      DatabaseCleaner.start

      task_plan = FactoryBot.create :tasked_task_plan, number_of_students: 1
      @ecosystem = task_plan.ecosystem
      @page = @ecosystem.pages.first
      @exercises = @page.exercises
      @course = task_plan.owner
      @task = task_plan.tasks.first
      @tasked_exercise = @task.tasked_exercises.first
      tasking = @task.taskings.first
      @period = tasking.period
      @student = tasking.role.student
    end

    after(:all) { DatabaseCleaner.clean }

    before(:each) do
      @course.reload
      @ecosystem.reload
    end

    let(:max_num_exercises) { 5 }

    context 'with default perform_later' do
      [
        [
          :create_ecosystem,
          -> { { ecosystem: @ecosystem.tap{ |eco| eco.update_attribute :sequence_number, 0 } } },
          OpenStax::Biglearn::Api::JobWithSequenceNumber,
          -> { @ecosystem },
          1
        ],
        [
          :create_course,
          -> { { course: @course.tap{ |course| course.update_attribute :sequence_number, 0 },
                 ecosystem: @ecosystem } },
          OpenStax::Biglearn::Api::JobWithSequenceNumber,
          -> { @course },
          1
        ],
        [
          :prepare_course_ecosystem,
          -> { { course: @course, ecosystem: @ecosystem } },
          Hash,
          -> { @course },
          1
        ],
        [
          :update_course_ecosystems,
          -> { [ { course: @course, preparation_uuid: SecureRandom.uuid } ] },
          OpenStax::Biglearn::Api::JobWithSequenceNumber,
          -> { @course },
          1
        ],
        [
          :sequentially_prepare_and_update_course_ecosystem,
          -> { { course: @course, ecosystem: @ecosystem } },
          Hash,
          -> { @course },
          2
        ],
        [
          :update_rosters,
          -> { [ { course: @course } ] },
          OpenStax::Biglearn::Api::JobWithSequenceNumber,
          -> { @course },
          1
        ],
        [
          :update_globally_excluded_exercises,
          -> { { course: @course } },
          OpenStax::Biglearn::Api::JobWithSequenceNumber,
          -> { @course },
          1
        ],
        [
          :update_course_excluded_exercises,
          -> { { course: @course } },
          OpenStax::Biglearn::Api::JobWithSequenceNumber,
          -> { @course },
          1
        ],
        [
          :update_course_active_dates,
          -> { { course: @course } },
          OpenStax::Biglearn::Api::JobWithSequenceNumber,
          -> { @course },
          1
        ],
        [
          :create_update_assignments,
          -> { [ { course: @course, task: @task } ] },
          OpenStax::Biglearn::Api::JobWithSequenceNumber,
          -> { @course },
          1
        ],
        [
          :record_responses,
          -> { [ { course: @course, tasked_exercise: @tasked_exercise } ] },
          OpenStax::Biglearn::Api::JobWithSequenceNumber,
          -> { @course },
          1
        ],
        [
          :fetch_assignment_pes,
          -> { [ { task: @task, max_num_exercises: max_num_exercises } ] },
          Hash,
          -> { @course },
          0
        ],
        [
          :fetch_assignment_spes,
          -> { [ { task: @task, max_num_exercises: max_num_exercises } ] },
          Hash,
          -> { @course },
          0
        ],
        [
          :fetch_practice_worst_areas_exercises,
          -> { [ { student: @student, max_num_exercises: max_num_exercises } ] },
          Hash,
          -> { @course },
          0
        ],
        [
          :fetch_student_clues,
          -> { [ { book_container: @page, student: @student } ] },
          Hash,
          -> { @course },
          0
        ],
        [
          :fetch_teacher_clues,
          -> { [ { book_container: @page, course_container: @period } ] },
          Hash,
          -> { @course },
          0
        ]
      ].each do |method, requests_proc, result_class, sequence_number_record_proc, increment|
        it "delegates #{method} to the client implementation and returns a job or response" do
          requests = instance_exec &requests_proc
          sequence_number_record = instance_exec &sequence_number_record_proc

          sequence_number = sequence_number_record.sequence_number \
            if sequence_number_record.present?

          expect(OpenStax::Biglearn::Api.client).to receive(method).and_call_original

          results = OpenStax::Biglearn::Api.send(method, requests)

          results = results.values if requests.is_a?(Array) && results.is_a?(Hash)

          [results].flatten.each { |result| expect(result).to be_a result_class }

          expect(sequence_number_record.reload.sequence_number).to(
            eq(sequence_number + increment)
          ) if sequence_number_record.present?
        end
      end
    end

    it 'converts returned exercise uuids to exercise objects, preserving their order' do
      exercises = @exercises.first(max_num_exercises).map do |exercise|
        Content::Exercise.new strategy: exercise.wrap
      end
      expect(Rails.logger).not_to receive(:warn)

      [ :fetch_assignment_pes, :fetch_assignment_spes ].each do |api_method|
        expect(OpenStax::Biglearn::Api.client).to receive(api_method) do |requests|
          requests.map do |request|
            {
              request_uuid: request[:request_uuid],
              exercise_uuids: exercises.map(&:uuid),
              assignment_status: 'assignment_ready'
            }
          end
        end.once

        result = nil
        expect do
          result = OpenStax::Biglearn::Api.public_send(
            api_method, task: @task, max_num_exercises: max_num_exercises
          )
        end.not_to raise_error
        expect(result.fetch(:accepted)).to eq true
        expect(result.fetch(:exercises)).to eq exercises
      end
    end

    it 'returns accepted: false and falls back to random personalized exercises' +
       ' if no valid Biglearn response' do
      [ :fetch_assignment_pes, :fetch_assignment_spes ].each do |api_method|
        expect(OpenStax::Biglearn::Api.client).to receive(api_method) do |requests|
          requests.map do |request|
            {
              request_uuid: request[:request_uuid],
              exercise_uuids: [],
              assignment_status: 'assignment_unready'
            }
          end
        end.exactly(3).times
        expect(Rails.logger).to receive(:warn).twice

        core_page_ids = GetTaskCorePageIds[tasks: @task][@task.id]

        result = nil
        expect do
          result = OpenStax::Biglearn::Api.public_send(
            api_method,
            task: @task,
            max_num_exercises: max_num_exercises,
            inline_sleep_interval: 0.01.second,
            inline_max_attempts: 3
          )
        end.not_to raise_error
        expect(result.fetch(:accepted)).to eq false
        exercises = result.fetch(:exercises)
        expect(exercises.size).to eq max_num_exercises
        exercises.each do |exercise|
          expect(core_page_ids).to include(exercise.content_page_id)
        end
      end
    end

    it 'errors when client returns more exercises than expected' do
      [ :fetch_assignment_pes, :fetch_assignment_spes ].each do |api_method|
        expect(OpenStax::Biglearn::Api.client).to receive(api_method) do |requests|
          requests.map do |request|
            {
              request_uuid: request[:request_uuid],
              exercise_uuids: (max_num_exercises + 1).times.map{ SecureRandom.uuid },
              assignment_status: 'assignment_ready'
            }
          end
        end
        expect(Rails.logger).not_to receive(:warn)

        expect do
          OpenStax::Biglearn::Api.public_send(
            api_method, task: @task, max_num_exercises: max_num_exercises
          )
        end.to raise_error{ OpenStax::Biglearn::Api::ExercisesError }
      end
    end

    it 'logs a warning when client returns less exercises than expected' do
      exercises = @exercises.first(max_num_exercises - 1).map do |exercise|
        Content::Exercise.new strategy: exercise.wrap
      end

      [ :fetch_assignment_pes, :fetch_assignment_spes ].each do |api_method|
        expect(OpenStax::Biglearn::Api.client).to receive(api_method) do |requests|
          requests.map do |request|
            {
              request_uuid: request[:request_uuid],
              exercise_uuids: exercises.map(&:uuid),
              assignment_status: 'assignment_ready'
            }
          end
        end
        expect(Rails.logger).to receive(:warn)

        result = nil
        expect do
          result = OpenStax::Biglearn::Api.public_send(
            api_method, task: @task, max_num_exercises: max_num_exercises
          )
        end.not_to raise_error
        expect(result.fetch(:exercises)).to match_array(exercises)
      end
    end

    it 'errors when client returns exercises not present locally' do
      [ :fetch_assignment_pes, :fetch_assignment_spes ].each do |api_method|
        expect(OpenStax::Biglearn::Api.client).to receive(api_method) do |requests|
          requests.map do |request|
            {
              request_uuid: request[:request_uuid],
              exercise_uuids: max_num_exercises.times.map{ SecureRandom.uuid },
              assignment_status: 'assignment_ready'
            }
          end
        end
        expect(Rails.logger).not_to receive(:warn)

        expect do
          OpenStax::Biglearn::Api.public_send(
            api_method, task: @task, max_num_exercises: max_num_exercises
          )
        end.to raise_error { OpenStax::Biglearn::Api::ExercisesError }
      end
    end
  end
end
