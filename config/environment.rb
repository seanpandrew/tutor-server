# Load the Rails application.
require File.expand_path('../application', __FILE__)

require 'delegate_access_control_to'
require 'date_time_utilities'

SITE_NAME = "OpenStax Tutor"
COPYRIGHT_HOLDER = "Rice University"

# Initialize the Rails application.
Rails.application.initialize!
