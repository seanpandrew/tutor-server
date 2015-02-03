class TaskStep < ActiveRecord::Base
  belongs_to :details, polymorphic: true, dependent: :destroy
  belongs_to :resource, dependent: :destroy
  belongs_to :task, inverse_of: :task_steps

  validates :details, presence: true
  validates :details_id, uniqueness: { scope: :details_type }
  validates :resource, presence: true
  validates :task, presence: true
  validates :number, presence: true,
                     uniqueness: { scope: :task_id },
                     numericality: true

  before_validation :assign_next_number

  delegate :url, :content, to: :resource

  protected

  def assign_next_number
    self.number ||= (peers.max_by{|p| p.number || -1}
                          .try(:number) || -1) + 1
  end

  def peers
    task.try(:task_steps) || []
  end
end
