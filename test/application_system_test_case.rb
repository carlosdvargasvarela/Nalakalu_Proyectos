require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # ponytail: Selenium Manager can't auto-discover/download a Chrome binary in
  # a network-restricted dev sandbox. CHROME_BIN (standard convention) wins if
  # set; otherwise fall back to whatever Selenium itself already cached locally
  # (a prior `chrome for testing` download), instead of hardcoding a path.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |capabilities|
    chrome_bin = ENV["CHROME_BIN"] || Dir.glob(File.expand_path("~/.cache/selenium/chrome/*/*/chrome")).max_by { |path| File.mtime(path) }
    capabilities.binary = chrome_bin if chrome_bin
  end
end
