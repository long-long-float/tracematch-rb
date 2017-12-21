module Tracematch
  class RegularExpressionEngine
    def initialize(src)
      tokens = tokenize(src)
      ast = parse(tokens)
      ast = reg_reverse(ast)
      compile(ast)
    end

    class VMThread < Thread
      def initialize(code, input, pc, sp, child_threads)
        super(code, input, pc, sp) do |code, input, pc, sp|
          while true
            inst = code[pc]
            case inst
            when Inst::Char
              if input[sp] != inst.c
                self[:state] = :fail
                break
              else
                pc += 1
                sp += 1
              end
            when Inst::Match
              self[:state] = sp
              break
            when Inst::Jmp
              pc = inst.x
            when Inst::Split
              pc = inst.x
              child_threads << VMThread.new(code, input, inst.y, sp, child_threads)
            when Inst::Label
              pc += 1
            end
          end
        end

        child_threads << self
      end
    end

    def match?(syms)
      child_threads = []
      VMThread.new(@code, syms.reverse, 0, 0, child_threads)

      index = child_threads.map { |thread|
        thread.join
        thread[:state]
      }.select {|state|
        state != :fail
      }.max

      if index
        true
      else
        false
      end
    end

    #
    # compiler
    #
    # ref: https://swtch.com/~rsc/regexp/regexp2.html
    #

    module Inst
      Char  = Struct::new(:c)
      Match = Class.new
      Jmp   = Struct::new(:x)
      Split = Struct::new(:x, :y)

      Label = Struct::new(:id)
    end

    def compile(ast)
      @code = []
      @label_count = 0
      compile_node(ast)
      @code << Inst::Match.new
      @code = resolve_label(@code)
    end

    def cur_addr
      @code.size
    end

    def label_new
      label = Inst::Label.new(@label_count)
      @label_count += 1
      label
    end

    def compile_node(node)
      case node
      when AST::Sequence
        compile_node(node.left)
        compile_node(node.right)
      when AST::Or
        l1 = label_new
        l2 = label_new
        l3 = label_new
        @code << Inst::Split.new(l1, l2)

        @code << l1
        compile_node(node.left)
        @code << Inst::Jmp.new(l3)

        @code << l2
        compile_node(node.right)

        @code << l3
      when AST::Repeatition
        case node.type
        when :zero_more
          l1 = label_new
          l2 = label_new
          l3 = label_new

          @code << l1
          @code << Inst::Split.new(l2, l3)

          @code << l2
          compile_node(node.regex)
          @code << Inst::Jmp.new(l1)

          @code << l3

        when :one_more
          l1 = label_new
          l3 = label_new

          @code << l1
          compile_node(node.regex)
          @code << Inst::Split.new(l1, l3)

          @code << l3

        else # n
          node.type.times do
            compile_node(node.regex)
          end
        end
      when AST::Leaf
        @code << Inst::Char.new(node.symbol)
      end
    end

    def resolve_label(code)
      label_addr = {}

      code.each.with_index do |inst, addr|
        if inst.is_a? Inst::Label
          label_addr[inst.id] = addr
        end
      end

      code.map {|inst|
        case inst
        when Inst::Jmp
          Inst::Jmp.new(label_addr[inst.x.id])
        when Inst::Split
          Inst::Split.new(label_addr[inst.x.id], label_addr[inst.y.id])
        else
          inst
        end
      }
    end

    # A B -> B A
    # A | B -> A | B
    # A* -> A*
    # A+ -> A+
    # A[n] -> A[n]
    # (A) -> (A)
    def reg_reverse(node)
      case node
      when AST::Sequence
        right = reg_reverse(node.right)
        left  = reg_reverse(node.left)
        AST::Sequence.new(right, left)
      when AST::Or
        right = reg_reverse(node.right)
        left  = reg_reverse(node.left)
        AST::Or.new(left, right)
      when AST::Repeatition
        reg = reg_reverse(node.regex)
        AST::Repeatition.new(reg, node.type)
      when AST::Leaf
        node
      end
    end

    #
    # parser
    #

    module TokenType
      Symbol       = 0
      Or           = 1 # |
      Asterisk     = 2 # *
      Plus         = 3 # +
      BraseLeft    = 4 # [
      BraseRight   = 5 # ]
      BracketLeft  = 6 # (
      BracketRight = 7 # )
      Constant     = 8 # number
    end

    Token = Struct.new(:type, :value)

    def tokenize(src)
      tokens = []
      i = 0
      while i < src.size
        ch = src[i]
        case ch
        when /[a-zA-Z_]/
          symbol = ''
          while src[i] =~ /[a-zA-Z_]/
            symbol += src[i]
            i += 1
          end
          i -= 1
          tokens << Token.new(TokenType::Symbol, symbol.to_sym)
        when '|'; tokens << Token.new(TokenType::Or, nil)
        when '*'; tokens << Token.new(TokenType::Asterisk, nil)
        when '+'; tokens << Token.new(TokenType::Plus, nil)
        when '['; tokens << Token.new(TokenType::BraseLeft, nil)
        when ']'; tokens << Token.new(TokenType::BraseRight, nil)
        when '('; tokens << Token.new(TokenType::BracketLeft, nil)
        when ')'; tokens << Token.new(TokenType::BracketRight, nil)
        when /[1-9]/
          num = ''
          while src[i] =~ /[0-9]/
            num += src[i]
            i += 1
          end
          i -= 1

          tokens << Token.new(TokenType::Constant, Integer(num))
        end

        i += 1
      end
      tokens
    end

    #
    # regex ::=
    #     regex_or
    #   | regex_or regex
    #
    # regex_or ::=
    #     regex_post
    #   | regex_post '|' regex
    #
    # regex_post ::=
    #     regex_term
    #   | regex_term '*'
    #   | regex_term '+'
    #   | regex_term '[' constant ']'
    #
    # regex_term ::=
    #     symbol
    #   | '(' regex ')'
    #

    module AST
      Sequence = Struct::new(:left, :right)
      Or       = Struct::new(:left, :right)
      Repeatition = Struct::new(:regex, :type) # type = :zero_more | :one_more | n
      Leaf     = Struct::new(:symbol)
    end

    def parse(tokens)
      @tokens = tokens
      @pos = 0

      parse_regex
    end

    def cur_token
      @tokens[@pos]
    end

    def cur_token_type
      tok = @tokens[@pos]
      tok && tok.type
    end

    def consume(token)
      raise "current tokens is not #{token}" unless cur_token.type == token
      @pos += 1
    end

    def parse_regex
      left = parse_regex_or
      if cur_token_type == TokenType::Symbol || cur_token_type == TokenType::BracketLeft
        right = parse_regex
        AST::Sequence.new(left, right)
      else
        left
      end
    end

    def parse_regex_or
      left = parse_regex_post
      if cur_token_type == TokenType::Or
        consume(TokenType::Or)
        right = parse_regex_post
        AST::Or.new(left, right)
      else
        left
      end
    end

    def parse_regex_post
      left = parse_regex_term
      type = nil
      case cur_token_type
      when TokenType::Asterisk
        consume(TokenType::Asterisk)
        type = :zero_more
      when TokenType::Plus
        consume(TokenType::Plus)
        type = :one_more
      when TokenType::BraseLeft
        consume(TokenType::BraseLeft)
        type = cur_token.value
        consume(TokenType::Constant)
        consume(TokenType::BraseRight)
      end
      if type
        AST::Repeatition.new(left, type)
      else
        left
      end
    end

    def parse_regex_term
      if cur_token_type == TokenType::Symbol
        leaf = AST::Leaf.new(cur_token.value)
        consume(TokenType::Symbol)
        leaf
      elsif cur_token_type == TokenType::BracketLeft
        consume(TokenType::BracketLeft)
        reg = parse_regex
        consume(TokenType::BracketRight)
        reg
      else
        raise "unexpected token #{cur_token}"
      end
    end
  end
end


