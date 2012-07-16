require 'shellwords' if RUBY_VERSION >= "1.9"

class Kicker
  class Job
    def self.attr_with_default(name, &default)
      # If `nil` this returns the `default`, unless explicitely set to `nil` by
      # the user.
      define_method(name) do
        if instance_variable_get("@#{name}_assigned")
          instance_variable_get("@#{name}")
        else
          instance_eval(&default)
        end
      end
      define_method("#{name}=") do |value|
        instance_variable_set("@#{name}_assigned", true)
        instance_variable_set("@#{name}", value)
      end
    end

    attr_accessor :command, :exit_code, :output

    def initialize(attributes)
      @exit_code = 0
      @output = ''
      attributes.each { |k,v| send("#{k}=", v) }
    end

    def success?
      exit_code == 0
    end

    attr_with_default(:print_before) do
      "Executing: #{command}"
    end

    attr_with_default(:print_after) do
      # Show all output if it wasn't shown before and the command fails.
      "\n#{output}\n\n" if Kicker.silent? && !success?
    end

    # TODO default titles??

    attr_with_default(:notify_before) do
      ["Kicker: Executing", command] unless Kicker.silent?
    end

    attr_with_default(:notify_after)  do
      message = Kicker.silent? ? "" : output
      if success?
        ["Kicker: Success", message]
      else
        ["Kicker: Failed (#{exit_code})", message]
      end
    end
  end

  module Utils #:nodoc:
    extend self

    attr_accessor :should_clear_screen
    alias_method :should_clear_screen?, :should_clear_screen

    def perform_work(command_or_options)
      if command_or_options.is_a?(Hash)
        options = command_or_options
      elsif command_or_options.is_a?(String)
        options = { :command => command_or_options }
      else
        raise ArgumentError, "Should be a string or a hash."
      end
      job = Job.new(options)
      will_execute_command(job)
      yield job
      did_execute_command(job)
      job
    end

    def execute(command_or_options)
      perform_work(command_or_options) do |job|
        _execute(job)
        yield job if block_given?
      end
    end

    def log(message)
      if Kicker.quiet
        puts message
      else
        now = Time.now
        puts "#{now.strftime('%H:%M:%S')}.#{now.usec.to_s[0,2]} | #{message}"
      end
    end
    
    def last_command_succeeded?
      $?.success?
    end
    
    def last_command_status
      $?.exitstatus
    end

    def clear_console!
      puts(CLEAR) if Kicker.clear_console?
    end

    private

    CLEAR = "\e[H\e[2J"

    def _execute(job)
      silent = Kicker.silent?
      unless silent
        puts
        sync_before, $stdout.sync = $stdout.sync, true
      end
      output = ""
      popen(job.command) do |io|
        while str = io.read(1)
          output << str
          $stdout.print str unless silent
        end
      end
      job.output = output.strip
      job.exit_code = last_command_status
      job
    ensure
      unless silent
        $stdout.sync = sync_before
        puts("\n\n")
      end
    end

    def popen(command, &block)
      if RUBY_VERSION >= "1.9"
        args = Shellwords.shellsplit(command)
        args << { :err => [:child, :out] }
        IO.popen(args, &block)
      else
        IO.popen("#{command} 2>&1", &block)
      end
    end
    
    def will_execute_command(job)
      puts(CLEAR) if Kicker.clear_console? && should_clear_screen?
      @should_clear_screen = false

      if message = job.print_before
        log(message)
      end

      if notification = job.notify_before
        Notification.notify(*notification)
      end
    end
    
    def did_execute_command(job)
      if message = job.print_after
        puts(message)
      end

      log(job.success? ? "Success" : "Failed (#{job.exit_code})")

      if notification = job.notify_after
        Notification.notify(*notification)
      end
    end
  end
end

module Kernel
  # Prints a +message+ with timestamp to stdout.
  def log(message)
    Kicker::Utils.log(message)
  end
  
  # When you perform some work (like shelling out a command to run without
  # using +execute+) you need to call this method, with a block in which you
  # perform your work, which will take care of logging the work appropriately.
  def perform_work(command, &block)
    Kicker::Utils.perform_work(command, &block)
  end
  
  # Executes the +command+, logs the output, and optionally sends user
  # notifications on Mac OS X (10.8 or higher).
  def execute(command, &block)
    Kicker::Utils.execute(command, &block)
  end
  
  # Returns the last executed command.
  def last_command
    Kicker::Utils.last_command
  end
end
