suppress_error = !ARGV.nil? && !ARGV.empty? && (ARGV[0].casecmp('--SILENT') == 0)

begin
  require "#{ENV['UNITY_DIR']}/auto/unity_test_summary.rb"

  build_dir = ENV.fetch('BUILD_DIR', './build')
  test_build_dir = ENV.fetch('TEST_BUILD_DIR', File.join(build_dir, 'test'))

  if test_build_dir.empty?
    results = Dir["#{build_dir}/**/*.testresult"]
  else
    results = Dir["#{test_build_dir}/*.testresult"]
  end

  parser = UnityTestSummary.new
  parser.targets = results
  parser.run
  puts parser.report
rescue StandardError => e
  raise e unless suppress_error
end

exit(parser.failures) unless suppress_error
