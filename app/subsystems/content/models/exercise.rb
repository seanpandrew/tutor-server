class Content::Exercise < ActiveRecord::Base
  acts_as_resource

  sortable_has_many :exercise_tags, on: :number,
                                    dependent: :destroy,
                                    inverse_of: :exercise

end
