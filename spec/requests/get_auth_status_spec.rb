require "rails_helper"

describe "Get authentication status", type: :request, version: :v1 do

  let(:application) { FactoryGirl.create :doorkeeper_application }
  let(:user)        { FactoryGirl.create(:user) }
  let(:anon_user)   { User::User.anonymous }


  describe "#status" do

    it 'returns false for current_user when user is anonymous' do
      stub_current_user(anon_user)
      get("/auth/status")
      expect(response).to have_http_status(:ok)
      expect(response.body_as_hash).to eq({current_user: false})
    end

    it 'returns a token and current_user when user is logged in' do
      stub_current_user(user)
      expect{
        get("/auth/status")
      }.to change{Doorkeeper::AccessToken.count}.by(1)
      expect(response).to have_http_status(:ok)
      token = Doorkeeper::AccessToken.find_by(resource_owner_id: user.id).token
      expect(response.body_as_hash).to match(
                                         :access_token => token,
                                         :current_user => {
                                           :name=>user.name,
                                           :is_admin=>false,
                                           :is_customer_service=>false,
                                           :is_content_analyst=>false,
                                           :profile_url=>a_string_starting_with("http")
                                         })
    end

    it 'sets cors headers' do
      get("/auth/status")
      expect(response.headers.keys).to include(
                                         'Access-Control-Allow-Origin',
                                         'Access-Control-Allow-Methods',
                                         'Access-Control-Request-Method',
                                         'Access-Control-Allow-Headers',
                                         'Access-Control-Allow-Credentials'
                                       )
    end

    it 'returns blank allow-origin if given one doesnt match' do
      get("/auth/status")
      expect(response).to have_http_status(:success)
      expect(response.headers['Access-Control-Allow-Origin']).to eq('')
    end

    it "should reply to a CORS OPTIONS request" do
      origin = Rails.application.secrets.cc_origins.first + '/foo/bar'
      # It's difficult to test an OPTIONS request
      # reset and __send__ hacks from https://github.com/rspec/rspec-rails/issues/925
      reset!
      integration_session.__send__ :process, 'OPTIONS', '/auth/status', nil, \
        {'HTTP_ORIGIN' => origin, 'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'GET'}
      expect(response.headers['Access-Control-Allow-Origin']).to eq(origin)
      expect(response.headers['Access-Control-Allow-Methods']).to eq('GET, OPTIONS')
    end

  end

end