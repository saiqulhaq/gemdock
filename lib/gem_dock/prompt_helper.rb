# frozen_string_literal: true

require "tty-prompt"

module GemDock
  # Helper module for consistent user prompts across CLI commands
  # Provides graceful degradation when TTY is not available (CI/CD environments)
  module PromptHelper
    class << self
      # Check if prompts are available (TTY terminal and not in CI mode)
      def prompts_available?
        !ci_mode? && $stdin.tty?
      end

      # Check if running in CI/CD environment
      def ci_mode?
        ENV["CI"] == "true" || ENV["GITHUB_ACTIONS"] == "true" || ENV["GITLAB_CI"] == "true"
      end

      # Create a new TTY::Prompt instance with consistent styling
      def prompt
        @prompt ||= TTY::Prompt.new(
          active_color: :cyan,
          help_color: :bright_black,
          interrupt: :exit
        )
      end

      # Ask a yes/no question with fallback for non-TTY
      # @param question [String] The question to ask
      # @param default [Boolean] Default value when prompts unavailable
      # @return [Boolean] User's response or default
      def yes_no(question, default: false)
        if prompts_available?
          prompt.yes?(question) do |q|
            q.default default
          end
        else
          puts "#{question} (#{default ? 'yes' : 'no'})"
          default
        end
      end

      # Select from a list of options
      # @param question [String] The question to ask
      # @param choices [Array, Hash] List of choices or hash with value => label
      # @param default [Object] Default selection (index or value)
      # @return [Object] Selected value
      def select(question, choices, default: nil)
        if prompts_available?
          prompt.select(question, choices, default: default, cycle: true)
        else
          # In non-TTY mode, return default or first choice
          result = default || (choices.is_a?(Hash) ? choices.keys.first : choices.first)
          puts "#{question} (selecting: #{result})"
          result
        end
      end

      # Multi-select from a list of options
      # @param question [String] The question to ask
      # @param choices [Array, Hash] List of choices
      # @param default [Array] Default selections
      # @return [Array] Selected values
      def multi_select(question, choices, default: [])
        if prompts_available?
          prompt.multi_select(question, choices, default: default)
        else
          puts "#{question} (selecting defaults: #{default.join(', ')})"
          default
        end
      end

      # Ask for text input
      # @param question [String] The question to ask
      # @param default [String] Default value
      # @param required [Boolean] Whether input is required
      # @return [String] User input or default
      def ask(question, default: nil, required: false)
        if prompts_available?
          prompt.ask(question) do |q|
            q.default default if default
            q.required required
          end
        else
          result = default || ""
          puts "#{question} (using: #{result})"
          result
        end
      end

      # Show a confirmation prompt with details
      # @param question [String] Main question
      # @param details [Array<String>] Additional details to show
      # @param default [Boolean] Default response
      # @return [Boolean] User's confirmation
      def confirm_with_details(question, details: [], default: false)
        if prompts_available?
          unless details.empty?
            puts ""
            details.each { |detail| puts "  #{detail}" }
            puts ""
          end
          prompt.yes?(question) do |q|
            q.default default
          end
        else
          unless details.empty?
            puts ""
            details.each { |detail| puts "  #{detail}" }
            puts ""
          end
          puts "#{question} (#{default ? 'yes' : 'no'})"
          default
        end
      end

      # Display a warning message with consistent styling
      # @param message [String] Warning message
      def warn(message)
        if prompts_available?
          prompt.warn(message)
        else
          puts "WARNING: #{message}"
        end
      end

      # Display an error message with consistent styling
      # @param message [String] Error message
      def error(message)
        if prompts_available?
          prompt.error(message)
        else
          puts "ERROR: #{message}"
        end
      end

      # Display a success message with consistent styling
      # @param message [String] Success message
      def success(message)
        if prompts_available?
          prompt.ok(message)
        else
          puts "✓ #{message}"
        end
      end
    end
  end
end
