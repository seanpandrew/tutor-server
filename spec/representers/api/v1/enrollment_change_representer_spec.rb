require 'rails_helper'

RSpec.describe Api::V1::EnrollmentChangeRepresenter, type: :representer do
  let!(:user)              do
    profile = FactoryGirl.create :user_profile
    strategy = ::User::Strategies::Direct::User.new(profile)
    ::User::User.new(strategy: strategy)
  end

  let!(:course)              { FactoryGirl.create(:entity_course) }
  let!(:period)              { ::CreatePeriod[course: course] }

  let!(:enrollment_change) { CourseMembership::CreateEnrollmentChange[
    user: user, period: period, requires_enrollee_approval: false
  ] }

  let(:representation)     { described_class.new(enrollment_change).as_json }

  it 'represents an enrollment change request' do
    expect(representation['id']).to eq enrollment_change.id.to_s
    expect(representation['from']).to be_nil
    expect(representation['to']['course']['id']).to eq period.course.id.to_s
    expect(representation['to']['course']['name']).to eq period.course.name
    expect(representation['to']['period']['id']).to eq period.id.to_s
    expect(representation['to']['period']['name']).to eq period.name
    expect(representation['status']).to eq enrollment_change.status.to_s
    expect(representation['requires_enrollee_approval']).to eq false
  end
end