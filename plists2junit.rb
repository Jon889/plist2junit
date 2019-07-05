#!/usr/bin/env ruby

# Modified from https://github.com/silverhammermba/plist2junit/blob/master/plist2junit.rb
# To combine multiple plists into one junit, eg when running UI tests multiple times and/or on multiple simulators
# Eg if running a test suite, split in half across 2 simulators, and running each half up to 2 times:
#   plist2junit.rb sim1try1.plist sim1try2.plist sim2try1.plist sim2try2.plist
# or
#   plist2junit.rb sim1try1.plist sim2try1.plist sim1try2.plist sim1try2.plist
# (as long as sim*try2.plist comes after sim*try1.plist)
# will provide the correct output, test results in sim*try2.plist's will override results in sim*try1.plist's
# (Assumes there is no overlap in the list of tests running on sim1 and sim2)

require 'json'

if ARGV.length < 1
  warn "usage: #$0 TestSummaries_try1.plist TestSummaries_try2.plist ... TestSummaries_tryN.plist"
  warn "test results in later arguments (TestSummaries_try(N+1).plist) override results in earlier arguments (TestSummaries_tryN.plist)"
  exit 1
end

# convert plist to a dictionary

$test_suites = {} # name: suite

def processPlist(plistPath)

  plist = nil
  IO.popen(%w{plutil -convert json -o -} << plistPath) do |plutil|
    plist = JSON.load plutil
  end

  # transform to a dictionary that mimics the output structure

  plist['TestableSummaries'].each do |target|
    test_classes = target["Tests"]

    # if the test target failed to launch at all
    if test_classes.empty? && target['FailureSummaries']
      name = target['TestName']
      $test_suites[name] = $test_suites[name] || {name: name, error: target['FailureSummaries'][0]['Message']}
      next
    end

    # else process the test classes in each target
    # first two levels are just summaries, so skip those
    test_classes[0]["Subtests"][0]["Subtests"].each do |test_class|
      suite_name = "#{target['TestName']}.#{test_class['TestName']}"
      suite = $test_suites[suite_name] || {name: suite_name, cases: {}}

      # process the tests in each test class
      test_class["Subtests"].each do |test|
        testcase = {name: test['TestName'], time: test['Duration']}

        if test['FailureSummaries']
          failure = test['FailureSummaries'][0]

          filename = failure['FileName']

          if filename == '<unknown>'
            testcase[:error] = failure['Message']
          else
            testcase[:failure] = failure['Message']
            testcase[:failure_location] = "#{filename}:#{failure['LineNumber']}"
          end
        end

      suite[:cases][testcase[:name]] = testcase
      end

      suite[:count] = suite[:cases].values.size
      suite[:failures] = suite[:cases].values.count { |testcase| testcase[:failure] }
      suite[:errors] = suite[:cases].values.count { |testcase| testcase[:error] }
    $test_suites[suite[:name]] = suite
    end
  end
end
ARGV.each do |plistPath|
  processPlist(plistPath)
end

total_test_count = $test_suites.values.inject(0) {|sum,x| sum + x[:count] }
# format the data

puts '<?xml version="1.0" encoding="UTF-8"?>'
puts "<testsuites tests='#{total_test_count}'>"
$test_suites.values.each do |suite|
  if suite[:error]
    puts "<testsuite name=#{suite[:name].encode xml: :attr} errors='1'>"
    puts "<error>#{suite[:error].encode xml: :text}</error>"
    puts '</testsuite>'
  else
    puts "<testsuite name=#{suite[:name].encode xml: :attr} tests='#{suite[:count]}' failures='#{suite[:failures]}' errors='#{suite[:errors]}'>"

    suite[:cases].values.each do |testcase|
      print "<testcase classname=#{suite[:name].encode xml: :attr} name=#{testcase[:name].encode xml: :attr} time='#{testcase[:time]}'"
      if testcase[:failure]
        puts '>'
        puts "<failure message=#{testcase[:failure].encode xml: :attr}>#{testcase[:failure_location].encode xml: :text}</failure>"
        puts '</testcase>'
      elsif testcase[:error]
        puts '>'
        puts "<error>#{testcase[:error].encode xml: :text}</error>"
        puts '</testcase>'
      else
        puts '/>'
      end
    end

    puts '</testsuite>'
  end
end
puts '</testsuites>'
