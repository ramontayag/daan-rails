require "test_helper"

class Daan::Core::WebFetchTest < ActiveSupport::TestCase
  setup do
    @workspace_dir = Dir.mktmpdir
    @workspace = Daan::Workspace.new(@workspace_dir)
    @tool = Daan::Core::WebFetch.new(workspace: @workspace)
  end

  teardown do
    FileUtils.rm_rf(@workspace_dir)
  end

  test "validates URL format" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    
    result = @tool.execute(url: "not-a-url")
    assert_match(/URL must be HTTP, HTTPS, or data URL/, result)
    
    result = @tool.execute(url: "ftp://example.com")
    assert_match(/URL must be HTTP, HTTPS, or data URL/, result)
  end

  test "handles timeout parameter" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    
    # Test with very short timeout to trigger timeout error
    result = @tool.execute(url: "https://httpbin.org/delay/5", timeout: 1)
    assert_match(/Timeout/, result)
  end

  test "returns error string on driver failure" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    
    # Test with invalid URL that will cause driver error
    result = @tool.execute(url: "https://this-domain-definitely-does-not-exist-12345.com")
    assert_match(/Error fetching/, result)
  end

  # Basic smoke test that requires Chrome to be installed
  # Skip if Chrome is not available
  test "fetches simple HTML content" do
    skip "Chrome not available" unless chrome_available?
    
    # Use a properly encoded data URL 
    encoded_html = "data:text/html,%3Chtml%3E%3Cbody%3E%3Ch1%3ETest%20Page%3C/h1%3E%3C/body%3E%3C/html%3E"
    result = @tool.execute(url: encoded_html)
    
    assert_includes result, "Test Page"
    assert_includes result, "<html>"
    assert_includes result, "<body>"
  end

  test "waits for selector when specified" do
    skip "Chrome not available" unless chrome_available?
    
    # Use properly encoded data URL with target div
    encoded_html = "data:text/html,%3Chtml%3E%3Cbody%3E%3Cdiv%20class%3D%27target%27%3ETarget%20Content%3C/div%3E%3C/body%3E%3C/html%3E"
    result = @tool.execute(
      url: encoded_html,
      wait_for_selector: ".target"
    )
    
    assert_includes result, "Target Content"
  end

  test "handles wait_for_selector timeout" do
    skip "Chrome not available" unless chrome_available?
    
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    
    # Use data URL without the expected selector
    encoded_html = "data:text/html,%3Chtml%3E%3Cbody%3E%3Cdiv%3ENo%20target%20here%3C/div%3E%3C/body%3E%3C/html%3E"
    result = @tool.execute(
      url: encoded_html,
      wait_for_selector: ".nonexistent",
      timeout: 1
    )
    
    assert_match(/Timeout/, result)
  end

  private

  def chrome_available?
    # Check if Chrome/Chromium is available
    system("which google-chrome > /dev/null 2>&1") ||
    system("which chromium-browser > /dev/null 2>&1") ||
    system("which chromium > /dev/null 2>&1")
  end
end