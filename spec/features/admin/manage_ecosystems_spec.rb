require 'rails_helper'
require 'vcr_helper'

RSpec.describe 'Administration', speed: :slow, vcr: VCR_OPTS do
  before do
    # Log in as admin
    admin = FactoryGirl.create(:user, :administrator)
    stub_current_user(admin)

    # Go to the admin console
    visit admin_root_path

    # Click on the "Ecosystems" tab
    click_link 'Ecosystems'
  end

  scenario 'imports a book' do
    click_link 'Import a new Ecosystem'

    fill_in 'Archive url', with: 'https://archive-staging-tutor.cnx.org/contents/'
    fill_in 'Book CNX id', with: '93e2b09d-261c-4007-a987-0b3062fe154b@4.4'
    click_button 'Import'

    expect(page).to have_css('.flash_notice', text: 'Ecosystem import job queued.')
    expect(page).to have_css('td', text: 'Physics')
    expect(page).to have_css('td', text: '4.4')
    expect(page).to have_css('[data-content="93e2b09d-261c-4007-a987-0b3062fe154b"]')
  end
end
