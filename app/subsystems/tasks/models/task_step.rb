class Tasks::Models::TaskStep < ApplicationRecord

  sortable_belongs_to :task, on: :number, inverse_of: :task_steps, touch: true
  belongs_to :tasked, polymorphic: true, dependent: :destroy, inverse_of: :task_step, touch: true
  belongs_to :page, subsystem: :content, inverse_of: :task_steps

  enum group_type: [
    :unknown_group,
    :core_group,
    :spaced_practice_group,
    :personalized_group,
    :recovery_group
  ]

  json_serialize :related_exercise_ids, Integer, array: true
  json_serialize :labels, String, array: true
  json_serialize :spy, Hash

  validates :task, presence: true
  validates :tasked, presence: true
  validates :tasked_id, uniqueness: { scope: :tasked_type }
  validates :group_type, presence: true

  delegate :can_be_answered?, :has_correctness?, :has_content?, to: :tasked

  scope :complete,   -> { where{first_completed_at != nil} }
  scope :incomplete, -> { where{first_completed_at == nil} }

  scope :exercises,  -> { where{tasked_type == Tasks::Models::TaskedExercise.name} }

  # Lock the task instead, but don't explode if task is nil
  def lock!(*args)
    task.try! :lock!, *args

    super
  end

  def exercise?
    tasked_type == Tasks::Models::TaskedExercise.name
  end

  def placeholder?
    tasked_type == Tasks::Models::TaskedPlaceholder.name
  end

  def is_correct?
    has_correctness? ? tasked.is_correct? : nil
  end

  def can_be_recovered?
    related_exercise_ids.any?
  end

  def make_correct!
    raise "Does not have correctness" unless has_correctness?
    tasked.make_correct!
  end

  def make_incorrect!
    raise "Does not have correctness" unless has_correctness?
    tasked.make_incorrect!
  end

  def complete!(completed_at: Time.current)
    valid?
    tasked.valid?
    tasked.before_completion
    tasked.errors.full_messages.each { |message| errors.add :tasked, message }
    return if errors.any?

    self.first_completed_at ||= completed_at
    self.last_completed_at = completed_at
    self.save!

    task.handle_task_step_completion!(completed_at: completed_at)
  end

  def completed?
    !first_completed_at.nil?
  end

  def feedback_available?
    completed? && task.feedback_available?
  end

  def group_name
    group_type.sub(/_group\z/, '').gsub('_', ' ')
  end

  def related_content
    page.nil? ? [] : [ page.related_content ]
  end

end
