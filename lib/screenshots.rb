do_screenshots = EnvUtilities.load_boolean(name: 'SSHOT', default: false)

if do_screenshots
  require 'capybara-screenshot/rspec'
  Capybara::Screenshot.autosave_on_failure = false
  Capybara::Screenshot.append_timestamp = false
  window_size = [1920, 6000]

  def screenshots_dir
    $screenshots_dir ||= Rails.root.join "tmp/capybara/screenshots_#{Time.now.strftime('%Y-%m-%d-%H-%M-%S')}"
  end

  def screenshot!(suffix: nil, width: nil, height: nil)
    include_html_screenshots = false

    page.driver.resize(width || window_size[0], height || window_size[1])

    original_save_path = Capybara.save_path
    begin
      Capybara.save_path = screenshots_dir
      saver = Capybara::Screenshot::Saver.new(
        Capybara, Capybara.page, include_html_screenshots, screenshot_base(suffix)
      )

      wait_for_ajax
      wait_for_animations

      if saver.save
        {:html => saver.html_path, :image => saver.screenshot_path}
      end
    ensure
      Capybara.save_path = original_save_path
    end
  end

  def capture_email!(address: nil, suffix: nil)
    open_email(address) if address.present?

    # Used to just call built-in `save_page`, but switched to below to add headers
    # current_email.save_page("#{screenshots_dir}/#{screenshot_base(suffix)}.html")

    path = "#{screenshots_dir}/#{screenshot_base(suffix)}.html"
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path,'w') do |f|
      f.write("Subject: #{current_email.subject}<br/>")
      f.write("To: #{current_email.to.join(', ')}<br/>")
      f.write("From: #{current_email.from.join(', ')}<br/>")
      f.write("--------------------<br/><br/>")
      f.write(current_email.body)
    end
  end

  def screenshot_base(suffix=nil)
    @screenshot_prefix_usage_counts ||= {}
    prefix = "#{self.class.description}_#{RSpec.current_example.description}".gsub(/\W+/,'_')
    @screenshot_prefix_usage_counts[prefix] ||= 0
    next_available_index = (@screenshot_prefix_usage_counts[prefix] += 1)
    "#{prefix}_#{next_available_index}#{'_' + suffix if suffix.present?}".gsub(/\W+/,'_')
  end

  def screenshots_enabled?; true; end
else
  def screenshot!(*args); end
  def capture_email!(*args); end
  def screenshots_enabled?; false; end
end
