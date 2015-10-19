class Catalog::Models::Offering < Tutor::SubSystems::BaseModel

  belongs_to :ecosystem

  validates :identifier,  presence: true
  validates :webview_url, presence: true
  validates :description, presence: true

end
