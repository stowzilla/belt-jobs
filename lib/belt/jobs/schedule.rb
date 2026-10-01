# frozen_string_literal: true

module Belt
  module Jobs
    module Schedule
      EXPRESSION = /\A(?:cron|rate)\(.+\)\z/i
      DAILY = /\A(?:every day|daily)(?: at)?\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\z/i
      INTERVAL = /\Aevery\s+(\d+)\s+(minute|minutes|hour|hours|day|days)\z/i

      module_function

      def compile(value)
        schedule = value.to_s.strip
        raise ConfigurationError, 'schedule cannot be blank' if schedule.empty?
        return schedule if schedule.match?(EXPRESSION)

        if (match = schedule.match(INTERVAL))
          amount = Integer(match[1], 10)
          raise ConfigurationError, 'schedule interval must be positive' unless amount.positive?

          unit = match[2].downcase
          unit = unit.sub(/s\z/, '') if amount == 1
          unit = "#{unit}s" if amount != 1 && !unit.end_with?('s')
          return "rate(#{amount} #{unit})"
        end

        if (match = schedule.match(DAILY))
          hour = Integer(match[1], 10)
          minute = Integer(match[2] || '0', 10)
          meridiem = match[3]&.downcase
          validate_clock!(hour, minute, meridiem)
          hour = (hour % 12) + 12 if meridiem == 'pm'
          hour %= 12 if meridiem == 'am'
          return "cron(#{minute} #{hour} * * ? *)"
        end

        raise ConfigurationError,
              "unsupported schedule #{schedule.inspect}; use cron(...), rate(...), " \
              "'every N minutes', or 'every day at 9am'"
      end

      def validate_clock!(hour, minute, meridiem)
        valid_hour = meridiem ? hour.between?(1, 12) : hour.between?(0, 23)
        return if valid_hour && minute.between?(0, 59)

        raise ConfigurationError, 'invalid daily schedule time'
      end
      private_class_method :validate_clock!
    end
  end
end
