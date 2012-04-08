require 'cgi'

module Formeze
  class Label
    def initialize(name)
      @name = name
    end

    def to_s
      @name.to_s.tr('_', ' ').capitalize
    end
  end

  class Field
    attr_reader :name

    def initialize(name, options = {})
      @name, @options = name, options
    end

    def validate(value, &error)
      error.call(self, 'is required') if required? && value !~ /\S/

      error.call(self, 'has too many lines') if !multiline? && value.lines.count > 1

      error.call(self, 'has too many characters') if value.chars.count > char_limit

      error.call(self, 'has too many words') if word_limit? && value.scan(/\w+/).length > word_limit

      error.call(self, 'is invalid') if pattern? && value !~ pattern

      error.call(self, 'is invalid') if values? && !values.include?(value)
    end

    def key
      @key ||= @name.to_s
    end

    def key_required?
      @options.fetch(:key_required) { true }
    end

    def label
      @label ||= @options.fetch(:label) { Label.new(name) }
    end

    def required?
      @options.fetch(:required) { true }
    end

    def multiline?
      @options.fetch(:multiline) { false }
    end

    def multiple?
      @options.fetch(:multiple) { false }
    end

    def char_limit
      @options.fetch(:char_limit) { 64 }
    end

    def word_limit?
      @options.has_key?(:word_limit)
    end

    def word_limit
      @options.fetch(:word_limit)
    end

    def pattern?
      @options.has_key?(:pattern)
    end

    def pattern
      @options.fetch(:pattern)
    end

    def values?
      @options.has_key?(:values)
    end

    def values
      @options.fetch(:values)
    end
  end

  module ArrayAttrAccessor
    def array_attr_reader(name)
      define_method(name) do
        ivar = :"@#{name}"

        values = instance_variable_get(ivar)

        if values.nil?
          values = []

          instance_variable_set(ivar, values)
        end

        values
      end
    end

    def array_attr_writer(name)
      define_method(:"#{name}=") do |value|
        ivar = :"@#{name}"

        values = instance_variable_get(ivar)

        if values.nil?
          instance_variable_set(ivar, [value])
        else
          values << value
        end
      end
    end

    def array_attr_accessor(name)
      array_attr_reader(name)
      array_attr_writer(name)
    end
  end

  module ClassMethods
    include ArrayAttrAccessor

    def fields
      @fields ||= []
    end

    def field(*args)
      field = Field.new(*args)

      fields << field

      if field.multiple?
        array_attr_accessor field.name
      else
        attr_accessor field.name
      end
    end

    def guard(&block)
      fields << block
    end

    def checks
      @checks ||= []
    end

    def check(&block)
      checks << block
    end

    def errors
      @errors ||= []
    end

    def error(message)
      errors << message
    end
  end

  class KeyError < StandardError; end

  class ValueError < StandardError; end

  class UserError < StandardError; end

  module InstanceMethods
    def parse(encoded_form_data)
      form_data = CGI.parse(encoded_form_data)

      self.class.fields.each do |field|
        unless field.respond_to?(:key)
          instance_eval(&field) ? return : next
        end

        unless form_data.has_key?(field.key)
          next if field.multiple? || !field.key_required?

          raise KeyError
        end

        values = form_data.delete(field.key)

        if values.length > 1
          raise ValueError unless field.multiple?
        end

        values.each do |value|
          field.validate(value) do |error|
            errors << UserError.new("#{field.label} #{error}")
          end

          send(:"#{field.name}=", value)
        end
      end

      raise KeyError unless form_data.empty?

      self.class.checks.zip(self.class.errors) do |check, error|
        instance_eval(&check) ? next : errors << UserError.new(error)
      end
    end

    def errors
      @errors ||= []
    end

    def valid?
      errors.empty?
    end
  end

  def self.setup(klass)
    klass.send :include, InstanceMethods

    klass.extend ClassMethods
  end
end
