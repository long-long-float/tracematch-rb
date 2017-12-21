require_relative './tracematch/regular_expression_engine.rb'

module Tracematch

  class Symbol
    attr_reader :calls, :name, :timing, :bind

    def initialize(name, timing)
      @name = name
      @timing = timing

      @bind = {
        returning: [],
        target: [],
      }

      @calls = []
    end

    def call(klass = nil, method, args)
      @calls << [klass, method, args]
      self
    end

    def returning(var)
      @bind[:returning] << var
      self
    end

    def target(var)
      @bind[:target] << var
      self
    end
  end

  class TracematchDefinition
    attr_reader :syms, :patterns, :variables

    class Token
    end

    def initialize(variables)
      @syms = []
      @patterns = []

      @variables = variables

      @token = Token.new
    end

    def sym(name, timing)
      s = Symbol.new(name, timing)
      @syms << s
      s
    end

    def _
      @token
    end

    def match(pattern, &advice)
      @patterns << [RegularExpressionEngine.new(pattern), advice]
    end
  end

  class TracematchRunner
    class BaseSandbox
    end

    class Sandbox
      def initialize(base_sandbox)
        @@base_sandbox = base_sandbox
      end

      def method_missing(name, *args)
        puts "through method #{name}"
        @@base_sandbox.send(name, *args)
      end

      def self.const_missing(name)
        puts "through const #{name}"
        @@base_sandbox.class.const_get(name)
      end
    end

    class Bind
      attr_reader :trace, :bind
      def initialize
        @trace = []
        @bind = {}
      end

      def match?(var_name, instance)
        @bind[var_name] == instance
      end

      def register(var_name, instance)
        raise "#{var_name} already registered" if @bind.key?(var_name)
        @bind[var_name] = instance
      end
    end

    def initialize(definition)
      @definition = definition

      @default_bind = Bind.new
      @binds = []
    end

    def find_sym(klass_name, method_name, args, timing)
      @definition.syms.find do |sym|
        next false unless sym.timing == timing

        sym.calls.find do |call|
          k, m, a = call
          k == klass_name && m == method_name # TODO: check args
        end
      end
    end

    def find_bind_or_register(var_name, instance)
      return @default_bind unless instance

      bind = @binds.find {|bind| bind.match?(var_name, instance) }
      if bind
        bind
      else
        bind = Bind.new
        bind.register(var_name, instance)
        @binds << bind
        bind
      end
    end

    def before_apply(instance, klass, name, args)
      sym = find_sym(klass, name, args, :before)
      if sym
        var, *rest = sym.bind[:target]
        bind = find_bind_or_register(var, instance)
        bind.trace << sym.name
      end
    end

    def after_apply(instance, klass, name, args)
      sym = find_sym(klass, name, args, :after)
      if sym
        var, *rest = sym.bind[:target]
        bind = find_bind_or_register(var, instance)
        bind.trace << sym.name
      end

      [@default_bind, @binds].flatten.each do |bind|
        @definition.patterns.each do |pattern|
          pattern, advice = pattern
          if pattern.match?(bind.trace)
            advice.call
          end
        end
      end
    end

    def run(def_src, code_src)
      BaseSandbox.class_eval(def_src)
      base_sandbox = BaseSandbox.new

      sandbox = Sandbox.new(base_sandbox)

      that = self

      @definition.variables.each do |name, klass_name|
        Sandbox.class_eval do
          base_sandbox = class_variable_get(:@@base_sandbox)
          klass_body = Class.new do

            @@klass_name = klass_name
            @@base_sandbox = base_sandbox
            @@that = that

            def initialize(*args)
              @@that.before_apply(nil, @@klass_name, :new, args)
              @base_inst = @@base_sandbox.class.const_get(@@klass_name).new(*args)
              @@that.after_apply(@base_inst, @@klass_name, :new, args)
            end

            def method_missing(name, *args)
              @@that.before_apply(@base_inst, @@klass_name, name, args)
              @base_inst.send(name, *args)
              @@that.after_apply(@base_inst, @@klass_name, name, args)
            end
          end

          const_set(klass_name, klass_body)
        end
      end

      @definition.syms.each do |sym|
        sym.calls.each do |call|
          klass_name, method_, args = call
          if klass_name == nil
            Sandbox.class_eval do
              base_sandbox = class_variable_get(:@@base_sandbox)
              define_method(method_) do |*args|
                that.before_apply(nil, nil, method_, args)
                base_sandbox.send(method_, *args)
                that.after_apply(nil, nil, method_, args)
              end
            end
          end
        end
      end

      sandbox.instance_eval(code_src)
    end
  end

  def self.tracematch(**variables, &body)
    td = TracematchDefinition.new(variables)
    td.instance_eval(&body)
    TracematchRunner.new(td)
  end
end

