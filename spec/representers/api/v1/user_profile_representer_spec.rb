require 'rails_helper'

RSpec.describe Api::V1::TaskPlanWithDetailedStatsRepresenter, :type => :representer do


  let(:user)           { FactoryGirl.build(:user_profile) }
  let(:representation) { Api::V1::UserProfileRepresenter.new(user).as_json }

  it "generates a JSON representation of a user that contains only the name" do
    expect(representation).to eq("name" => user.name)
  end

end
