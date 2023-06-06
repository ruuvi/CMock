require 'fileutils'
require 'yaml'
require 'optparse'

project_config_name = 'project.yml'

if ENV['CEEDLING_MAIN_PROJECT_FILE']
  project_config_name = ENV['CEEDLING_MAIN_PROJECT_FILE']  # override default project config
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: create_makefile.rb [options]"

  opts.on('-c', '--project_config PATH', 'Path to the project.yml file') do |v|
    options[:project_config] = v
  end
end.parse!

if options[:project_config]
  project_config_name = options[:project_config]  # override default and environment project config
end

project_suffix_match_data = project_config_name.match(/project(_\w+)\.yml/)
project_suffix = project_suffix_match_data ? project_suffix_match_data[1] : ''

project_name = File.basename(project_config_name, File.extname(project_config_name))
PROJECT_TEST_CFLAGS_MACRO = "TEST_CFLAGS_#{project_name.upcase}"
PROJECT_TEST_LDFLAGS_MACRO = "TEST_LDFLAGS_#{project_name.upcase}"

project_config = nil
if File.file?(project_config_name)
  project_config = YAML.load_file(project_config_name)
end
CEEDLING_MAIN_PROJECT_FILE = project_config ? "CEEDLING_MAIN_PROJECT_FILE=#{project_config_name}" : ""


ABS_ROOT = FileUtils.pwd
CMOCK_DIR = File.expand_path(ENV.fetch('CMOCK_DIR', File.join(ABS_ROOT, '..', '..')))
require "#{CMOCK_DIR}/lib/cmock"
UNITY_DIR = File.join(CMOCK_DIR, 'vendor', 'unity')
require "#{UNITY_DIR}/auto/generate_test_runner"

SRC_DIR = nil
if project_config
  paths_with_wildcards = project_config[:paths][:source]
else
  SRC_DIR = ENV.fetch('SRC_DIR',  './src')
  paths_with_wildcards = ["#{SRC_DIR}"]
end

executable_extension = project_config&.dig(:extension, :executable) || ''

project_defines = project_config&.dig(:defines, :test)&.flatten || []
project_linker_flags = project_config&.dig(:tools, :test_linker, :arguments) || []
project_linker_flags.reject! { |arg| arg.include?('$') }

list_of_paths_without_wildcards = []

paths_with_wildcards.each do |path|
  # Remove any trailing wildcards and slashes
  base_path = path.chomp('**').chomp('*').chomp('/')

  # Add the base path
  list_of_paths_without_wildcards << base_path

  # If the path includes a '**', add all subdirectories
  if path.include?('**')
    Dir.glob("#{base_path}/**/").each do |subdir|
      list_of_paths_without_wildcards << subdir.chomp('/')
    end
    # If the path includes a '*', add all direct subdirectories
  elsif path.include?('*')
    Dir.glob("#{base_path}/*/").each do |subdir|
      list_of_paths_without_wildcards << subdir.chomp('/')
    end
  end
end
# Remove duplicates
list_of_paths_without_wildcards.uniq!


all_sources = []
list_of_paths_without_wildcards.each do |path|
  files = Dir.glob("#{path}/*.{c,cpp}")
  all_sources.concat(files)
end

all_sources_dict = all_sources.each_with_object({}) do |file_path, hash|
  file_name = File.basename(file_path)
  hash[file_name] = file_path
end

# headers that begin with prefix or end with suffix are not included
all_headers = []
list_of_paths_without_wildcards.each do |path|
  files = Dir.glob("#{path}/*.{h,hpp}")
  all_headers.concat(files)
end
all_headers_dict = all_headers.each_with_object({}) do |file_path, hash|
  file_name = File.basename(file_path)
  hash[file_name] = file_path
end

include_paths = []
all_headers.each do |file|
  include_paths << File.dirname(file)
end
include_paths.uniq!
include_paths_c_flags = include_paths.map { |dir| "-I #{dir}" }.join(' ')


if project_config
  paths_test = project_config[:paths][:test]
else
  TEST_DIR = ENV.fetch('TEST_DIR', './test')
  paths_test = ["#{TEST_DIR}/**"]
end
# We'll build up our list of sources in this array
test_sources = []
paths_test.each do |path|
  if path.start_with?('+:') || path.start_with?('-:')
    operator = path.slice!(0,2)[0]
  else
    operator = '+'
  end
  # If the path ends with '**', we'll look for test_*.c files in this directory and all subdirectories
  if path.end_with?('**')
    base_path = path.chomp('**').chomp('/')
    Dir.glob("#{base_path}/**/test_*.c").each do |file|
      operator == '+' ? test_sources << file : test_sources.delete(file)
    end
    # If the path ends with '*', we'll look for test_*.c files only in this directory
  elsif path.end_with?('*')
    base_path = path.chomp('*').chomp('/')
    Dir.glob("#{base_path}/test_*.c").each do |file|
      operator == '+' ? test_sources << file : test_sources.delete(file)
    end
  else
    # If the path doesn't end with a wildcard, we'll just look for test_*.c files in this exact directory
    # We'll also add a '/' to the end of the path if it's not already present, to make sure it's treated as a directory
    path << '/' unless path.end_with?('/')
    Dir.glob("#{path}test_*.c").each do |file|
      operator == '+' ? test_sources << file : test_sources.delete(file)
    end
  end
end


UNITY_SRC = File.join(UNITY_DIR, 'src')
CMOCK_SRC = File.join(CMOCK_DIR, 'src')
BUILD_DIR = ENV.fetch('BUILD_DIR', project_config&.dig(:project, :build_root) || './build')
TEST_BUILD_DIR = ENV.fetch('TEST_BUILD_DIR', File.join(BUILD_DIR, 'test'))
TEST_OUT_DIR = ENV.fetch('TEST_OUT_DIR', File.join(TEST_BUILD_DIR, 'out'))
OUT_DIR = TEST_OUT_DIR
OBJ_DIR = File.join(OUT_DIR, 'c')
ASM_DIR = File.join(OUT_DIR, 'asm')
UNITY_OBJ = File.join(OBJ_DIR, 'unity.o')
CMOCK_OBJ = File.join(OBJ_DIR, 'cmock.o')
RUNNERS_DIR = File.join(TEST_BUILD_DIR, 'runners')
MOCKS_DIR = File.join(TEST_BUILD_DIR, 'mocks')
TEST_BIN_DIR = OUT_DIR
MOCK_PREFIX = ENV.fetch('TEST_MOCK_PREFIX', 'mock_')
MOCK_SUFFIX = ENV.fetch('TEST_MOCK_SUFFIX', '')
TEST_MAKEFILE = ENV.fetch('TEST_MAKEFILE', File.join(TEST_BUILD_DIR, 'MakefileTestSupport'))
MOCK_MATCHER = /#{MOCK_PREFIX}[A-Za-z_][A-Za-z0-9_\-\.]+#{MOCK_SUFFIX}/

[TEST_BUILD_DIR, OUT_DIR, OBJ_DIR, ASM_DIR, RUNNERS_DIR, MOCKS_DIR, TEST_BIN_DIR].each do |dir|
  FileUtils.mkdir_p dir
end

all_headers_to_mock = []

suppress_error = !ARGV.nil? && !ARGV.empty? && (ARGV[0].casecmp('--SILENT') == 0)

File.open(TEST_MAKEFILE, 'w') do |mkfile|
  # Define make variables
  mkfile.puts 'CC ?= gcc'
  mkfile.puts "CMOCK_DIR ?= #{CMOCK_DIR}"
  mkfile.puts "UNITY_DIR ?= #{UNITY_DIR}"
  mkfile.puts ''
  mkfile.puts "#{PROJECT_TEST_CFLAGS_MACRO} = -g #{project_defines.map { |define| "-D#{define}" }.join(' ')}"
  test_sources.each do |test|
    test_basename = File.basename(test, File.extname(test))
    test_defines = project_config&.dig(:defines, test_basename.to_sym)&.flatten || []
    test_cflags_macro = "TEST_CFLAGS_#{project_name.upcase}_#{test_basename.upcase}"
    if test_defines.empty?
      mkfile.puts "#{test_cflags_macro} = ${#{PROJECT_TEST_CFLAGS_MACRO}}"
    else
      mkfile.puts "#{test_cflags_macro} = -g #{test_defines.map { |define| "-D#{define}" }.join(' ')}"
    end
  end
  mkfile.puts ''
  mkfile.puts "#{PROJECT_TEST_LDFLAGS_MACRO} = #{project_linker_flags.join(' ')}"
  mkfile.puts ''

  # Build Unity
  mkfile.puts "#{UNITY_OBJ}: #{UNITY_SRC}/unity.c"
  mkfile.puts "\t${CC} -o $@ -c $< -I #{UNITY_SRC}"
  mkfile.puts ''

  # Build CMock
  mkfile.puts "#{CMOCK_OBJ}: #{CMOCK_SRC}/cmock.c"
  mkfile.puts "\t${CC} -o $@ -c $< -I #{UNITY_SRC} -I #{CMOCK_SRC}"
  mkfile.puts ''

  mkfile.puts ".PHONY: generate_cmock_mocks_and_runners"
  mkfile.puts ''

  test_targets = []
  all_tests_results = []
  generator = UnityTestRunnerGenerator.new

  def reject_mock_files(file)
    extn = File.extname file
    filename = File.basename file, extn
    if MOCK_SUFFIX.empty?
      return filename.start_with? MOCK_PREFIX
    end

    (filename.start_with?(MOCK_PREFIX) || filename.end_with?(MOCK_SUFFIX))
  end

  all_headers = all_headers.reject { |f| reject_mock_files(f) }

  makefile_targets = []

  test_sources.each do |test|
    test_basename = File.basename(test, File.extname(test))
    test_cflags_macro = "TEST_CFLAGS_#{project_name.upcase}_#{test_basename.upcase}"
    module_name = File.basename(test, '.c')
    src_module_name = module_name.sub(/^test_/, '')
    test_obj = File.join(OBJ_DIR, "#{module_name}.o")
    runner_source = File.join(RUNNERS_DIR, "runner_#{module_name}.c")
    runner_obj = File.join(OBJ_DIR, "runner_#{module_name}.o")
    test_bin = File.join(TEST_BIN_DIR, module_name + executable_extension)
    test_results = File.join(TEST_BIN_DIR, module_name + '.testresult')

    cfg = {
      src: test,
      includes: generator.find_includes(File.readlines(test).join(''))
    }

    # Build main project modules, with TEST defined
    module_src = all_sources_dict["#{src_module_name}.c"]
    module_obj = File.join(OBJ_DIR, "#{src_module_name}.o")
    unless makefile_targets.include? module_obj
      makefile_targets.push(module_obj)
      header_deps = cfg[:includes][:local].select { |name| name =~ MOCK_MATCHER }.map { |name| File.join(MOCKS_DIR, name) }.join(' ')
      mkfile.puts "#{module_obj}: #{module_src} #{header_deps}"
      mkfile.puts "\t${CC} -o $@ -c $< ${#{test_cflags_macro}} -I #{File.dirname(module_src)} #{include_paths_c_flags} ${INCLUDE_PATH}"
      mkfile.puts ''
    end

    local_deps = cfg[:includes][:local].reject { |name| name =~ MOCK_MATCHER }
    local_deps.map! { |name| File.basename(name, File.extname(name)) }
    local_deps.reject! { |name| name == src_module_name }
    local_deps.select! { |name| all_sources_dict.has_key?("#{name}.c") }
    local_deps_objs = local_deps.map { |name| File.join(OBJ_DIR, "#{name}.o") }
    local_deps.each do |name|
      local_deps_obj = File.join(OBJ_DIR, "#{name}.o")
      unless makefile_targets.include? local_deps_obj
        makefile_targets.push(local_deps_obj)
        local_deps_src_path = all_sources_dict["#{name}.c"]
        local_deps_header_path = all_headers_dict["#{name}.h"]
        mkfile.puts "#{local_deps_obj}: #{local_deps_src_path} #{local_deps_header_path}"
        mkfile.puts "\t${CC} -o $@ -c $< ${#{test_cflags_macro}} -I #{File.dirname(module_src)} #{include_paths_c_flags} ${INCLUDE_PATH}"
        mkfile.puts ''
      end
    end


    # process link-only files
    linkonly = cfg[:includes][:linkonly]
    linkonly_objs = []
    linkonly.each do |linkonlyfile|
      linkonlybase = File.basename(linkonlyfile, '.*')
      linkonlymodule_src = File.join(SRC_DIR, linkonlyfile.to_s)
      linkonlymodule_obj = File.join(OBJ_DIR, "#{linkonlybase}.o")
      linkonly_objs.push(linkonlymodule_obj)
      # only create the target if we didn't already
      next if makefile_targets.include? linkonlymodule_obj

      makefile_targets.push(linkonlymodule_obj)
      mkfile.puts "#{linkonlymodule_obj}: #{linkonlymodule_src}"
      mkfile.puts "\t${CC} -o $@ -c $< ${#{test_cflags_macro}} -I ${SRC_DIR} ${INCLUDE_PATH}"
      mkfile.puts ''
    end

    # Create runners
    mkfile.puts "#{runner_source}: #{test}"
    mkfile.puts "\t@UNITY_DIR=${UNITY_DIR} PROJECT_BUILD_ROOT=#{BUILD_DIR} #{CEEDLING_MAIN_PROJECT_FILE} ruby ${CMOCK_DIR}/scripts/create_runner.rb #{test} #{runner_source}"
    mkfile.puts ''

    mkfile.puts "generate_cmock_mocks_and_runners: #{runner_source}"
    mkfile.puts ''

    # Build runner
    mkfile.puts "#{runner_obj}: #{runner_source}"
    mkfile.puts "\t${CC} -o $@ -c $< ${#{test_cflags_macro}} #{include_paths_c_flags} -I #{MOCKS_DIR} -I #{UNITY_SRC} -I #{CMOCK_SRC} ${INCLUDE_PATH}"
    mkfile.puts ''

    # Collect mocks to generate
    system_mocks = cfg[:includes][:system].select { |name| name =~ MOCK_MATCHER }
    raise 'Mocking of system headers is not yet supported!' unless system_mocks.empty?

    local_mocks = cfg[:includes][:local].select { |name| name =~ MOCK_MATCHER }

    module_names_to_mock = local_mocks.map { |name| name.sub(/#{MOCK_PREFIX}/, '').to_s }
    headers_to_mock = []
    module_names_to_mock.each do |name|
      header_to_mock = nil
      all_headers.each do |header|
        if header =~ /[\/\\]?#{name}$/
          header_to_mock = header
          break
        end
      end
      raise "Module header '#{name}' not found to mock!" unless header_to_mock

      headers_to_mock << header_to_mock
    end

    all_headers_to_mock += headers_to_mock
    mock_objs = headers_to_mock.map do |hdr|
      mock_name = MOCK_PREFIX + File.basename(hdr, '.*')
      File.join(OBJ_DIR, mock_name + '.o')
    end
    all_headers_to_mock.uniq!

    # Build test suite
    mkfile.puts "#{test_obj}: #{test} #{module_obj} #{mock_objs.join(' ')}"
    mkfile.puts "\t${CC} -o $@ -c $< ${#{test_cflags_macro}} #{include_paths_c_flags} -I #{UNITY_SRC} -I #{CMOCK_SRC} -I #{MOCKS_DIR} ${INCLUDE_PATH}"
    mkfile.puts ''

    # Build test suite executable
    test_objs = "#{test_obj} #{runner_obj} #{module_obj} #{mock_objs.join(' ')} #{local_deps_objs.join(' ')} #{linkonly_objs.join(' ')} #{UNITY_OBJ} #{CMOCK_OBJ}"
    mkfile.puts "#{test_bin}: #{test_objs}"
    mkfile.puts "\t${CC} -o $@ #{test_objs} ${LDFLAGS} ${#{PROJECT_TEST_LDFLAGS_MACRO}}"
    mkfile.puts ''

    mkfile.puts ".PHONY: #{module_name}"
    mkfile.puts ''
    mkfile.puts "#{module_name}: #{test_bin}"
    mkfile.puts ''
    mkfile.puts "TEST_TARGETS += #{module_name}"
    mkfile.puts ''

    # Run test suite and generate report
    mkfile.puts "#{test_results}: #{test_bin}"
    mkfile.puts "\t-#{test_bin} > #{test_results} 2>&1"
    mkfile.puts ''

    test_targets << test_bin
    all_tests_results << test_results
  end

  # Generate and build mocks

  all_headers_to_mock.each do |hdr|
    mock_name = MOCK_PREFIX + File.basename(hdr, '.*')
    mock_header = File.join(MOCKS_DIR, mock_name + File.extname(hdr))
    mock_src = File.join(MOCKS_DIR, mock_name + '.c')
    mock_obj = File.join(OBJ_DIR, mock_name + '.o')

    mkfile.puts "#{mock_src} #{mock_header}: #{hdr}"
    mkfile.puts "\t@CMOCK_DIR=${CMOCK_DIR} PROJECT_BUILD_ROOT=#{BUILD_DIR} MOCK_OUT=#{MOCKS_DIR} #{CEEDLING_MAIN_PROJECT_FILE} ruby ${CMOCK_DIR}/scripts/create_mock.rb #{hdr}"
    mkfile.puts ''

    mkfile.puts "#{mock_obj}: #{mock_src} #{mock_header}"
    mkfile.puts "\t${CC} -o $@ -c $< ${#{PROJECT_TEST_CFLAGS_MACRO}} -I #{MOCKS_DIR} #{include_paths_c_flags} -I #{UNITY_SRC} -I #{CMOCK_SRC} ${INCLUDE_PATH}"
    mkfile.puts ''

    mkfile.puts "generate_cmock_mocks_and_runners: #{mock_src} #{mock_header}"
    mkfile.puts ''
  end

  # Create target to run all tests
  mkfile.puts ".PHONY:  test"
  mkfile.puts ''
  mkfile.puts "test:  #{all_tests_results.join(' ')}"
  mkfile.puts ''

  # Create test summary task
  mkfile.puts "ifndef DISABLE_CMOCK_TEST_SUMMARY_PER_PROJECT"
  mkfile.puts ''
  mkfile.puts ".PHONY: test_summary#{project_suffix}"
  mkfile.puts ''
  mkfile.puts "test_summary#{project_suffix}:"
  mkfile.puts "\t@UNITY_DIR=${UNITY_DIR} BUILD_DIR=#{BUILD_DIR} TEST_BUILD_DIR= ruby ${CMOCK_DIR}/scripts/test_summary.rb #{suppress_error ? '--silent' : ''}"
  mkfile.puts ''

  mkfile.puts "test:  test_summary#{project_suffix}"
  mkfile.puts ''
  mkfile.puts "endif"

end
