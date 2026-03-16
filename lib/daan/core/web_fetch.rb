require "selenium-webdriver"

module Daan
  module Core
    class WebFetch < RubyLLM::Tool
      description "Fetch web content using Selenium WebDriver to render JavaScript and return full HTML"
      
      params({
        type: "object",
        properties: {
          "url" => {
            type: "string",
            description: "The URL to fetch"
          },
          "timeout" => {
            type: "number",
            description: "Timeout in seconds (default: 10)"
          },
          "wait_for_selector" => {
            type: "string",
            description: "Optional CSS selector to wait for before returning content"
          }
        },
        required: [ "url" ],
        additionalProperties: false,
        strict: true
      })

      def initialize(workspace: nil, chat: nil, **)
        @workspace = workspace
      end

      DEFAULT_TIMEOUT = 10

      def execute(url:, timeout: DEFAULT_TIMEOUT, wait_for_selector: nil)
        validate_url(url)
        
        driver = nil
        begin
          driver = create_driver(timeout)
          driver.get(url)
          
          # Wait for optional selector if provided
          if wait_for_selector
            wait = Selenium::WebDriver::Wait.new(timeout: timeout)
            wait.until { driver.find_element(css: wait_for_selector) }
          end
          
          # Return the full page HTML
          driver.page_source
          
        rescue Selenium::WebDriver::Error::TimeoutError => e
          raise "Timeout after #{timeout}s waiting for page to load: #{e.message}"
        rescue Selenium::WebDriver::Error::WebDriverError => e
          raise "Error fetching #{url}: WebDriver error: #{e.message}"
        rescue URI::InvalidURIError => e
          raise "Invalid URL: #{e.message}"
        rescue StandardError => e
          raise "Error fetching #{url}: #{e.message}"
        ensure
          driver&.quit
        end
      end

      private

      def validate_url(url)
        uri = URI.parse(url)
        # Allow HTTP, HTTPS, and data URLs for testing
        unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS) || uri.scheme == 'data'
          raise "URL must be HTTP, HTTPS, or data URL: #{url}"
        end
      end

      def create_driver(timeout)
        options = Selenium::WebDriver::Chrome::Options.new
        
        # Headless mode for performance
        options.add_argument('--headless')
        options.add_argument('--disable-gpu')
        options.add_argument('--no-sandbox')
        options.add_argument('--disable-dev-shm-usage')
        options.add_argument('--window-size=1920,1080')
        
        # Disable unnecessary features for performance
        options.add_argument('--disable-extensions')
        options.add_argument('--disable-plugins')
        options.add_argument('--disable-images')
        
        # Set user agent to look like a real browser
        options.add_argument('--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
        
        driver = Selenium::WebDriver.for(:chrome, options: options)
        
        # Set timeouts
        driver.manage.timeouts.page_load = timeout
        driver.manage.timeouts.script_timeout = timeout
        driver.manage.timeouts.implicit_wait = 3 # Short implicit wait for element finding
        
        driver
      end
    end
  end
end