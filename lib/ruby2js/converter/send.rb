module Ruby2JS
  class Converter

    # (send nil :puts
    #   (int 1))

    # (attr nil :puts)

    # (sendw nil :puts
    #   (int 1))

    # Note: attr, sendw, send!, and await are only generated by filters.  Attr forces
    # interpretation as an attribute vs a function call with zero parameters.
    # send! forces interpretation as a method call even with zero parameters.
    # Sendw forces parameters to be placed on separate lines.

    handle :send, :sendw, :send!, :await, :attr, :call do |receiver, method, *args|
      ast = @ast

      if \
        args.length == 1 and method == :+
      then
        node = collapse_strings(ast)
        return parse node if node != ast
      end

      # :irange support
      # - currently only .to_a
      if \
        receiver and
        receiver.type == :begin and
        [:irange, :erange].include? receiver.children.first.type
      then
        unless method == :to_a
          raise Error.new("#{receiver.children.first.type} can only be converted to array currently", receiver.children.first)
        else
          return range_to_array(receiver.children.first)
        end
      end

      # strip '!' and '?' decorations
      method = method.to_s[0..-2] if method =~ /\w[!?]$/ && !WEBDRIVER_HELPER_COMMANDS.keys.include?(method)

      # anonymous class
      if method == :new and receiver and receiver.children == [nil, :Class] and
        args.last.type == :def and args.last.children.first == nil

        parent = (args.length > 1) ? args.first : nil

        if es2015
          return parse s(:class2, nil, parent, *args.last.children[2..-1])
        else
          return parse s(:kwbegin, s(:class, s(:const, nil, :$$), parent,
            *args.last.children[2..-1]), s(:const, nil, :$$))
        end
      end

      # three ways to define anonymous functions
      if method == :new and receiver and receiver.children == [nil, :Proc]
        return parse args.first, @state

      elsif not receiver and [:lambda, :proc].include? method
        if method == :lambda and @state != :statement
          return parse s(args.first.type, *args.first.children[0..-2],
            s(:autoreturn, args.first.children[-1])), @state
        else
          return parse args.first, @state
        end
      end

      # call anonymous function
      if [:call, :[]].include? method and receiver and receiver.type == :block
        t2,m2,*args2 = receiver.children.first.children
        if not t2 and [:lambda, :proc].include? m2 and args2.length == 0
          (es2015 || @state == :statement ? group(receiver) : parse(receiver))
          put '('; parse_all(*args, join: ', '); put ')'
          return
        elsif not t2 and m2 == :async and args2.length == 0
          put '('; parse receiver; put ')()'
          return
        end
      end

      # async/await support
      # map "await x do...end" to "await x {...}" due to precedence rules
      if method == :await and es2017 and receiver == nil and args.length == 2 and args[1].type == :def
        args = [s(:block, args.first, *args.last.children[1..-1])]
      end
      if es2017 and receiver == nil and args.length == 1
        if method == :async
          if args.first.type == :def
            # async def f(x) {...}
            return parse args.first.updated :async

          elsif args.first.type == :defs
            # async def o.m(x) {...}
            return parse args.first.updated :asyncs

          elsif args.first.type == :send  and 
            args.first.children.first.type == :block and 
            args.first.children.last == :[]

            put '(async '
            parse args.first.children.first, :statement
            put ')()'
            return

          elsif args.first.type == :block
            block = args.first

            if block.children[0].children.last == :lambda
              # async lambda {|x| ... }
              # async -> (x) { ... }
              return parse block.updated(:async, [nil, block.children[1],
                s(:autoreturn, block.children[2])])

            elsif block.children[0].children.last == :proc
              # async proc {|x| ... }
              return parse block.updated(:async, [nil, *block.children[1..-1]])

            elsif \
              block.children[0].children[1] == :new and
              block.children[0].children[0] == s(:const, nil, :Proc)
            then
              # async Proc.new {|x| ... }
              return parse block.updated(:async, [nil, *block.children[1..-1]])
            end
          end

        elsif method == :await
          if args.first.type == :send
            # await f(x)
            return parse args.first.updated(:await)

          elsif args.first.type == :block
            # await f(x) { ... }
            block = args.first
            return parse block.updated nil, [block.children[0].updated(:await),
              *block.children[1..-1]]
          end
        end
      end

      op_index = operator_index method
      if op_index != -1
        target = args.first
      end

      # resolve anonymous receivers against rbstack
      receiver ||= @rbstack.map {|rb| rb[method]}.compact.last
      autobind = nil

      if receiver
        if receiver.type == :autobind
          autobind = receiver = receiver.children.first
          autobind = nil unless @autobind
        end

        group_receiver = receiver.type == :send &&
          op_index < operator_index( receiver.children[1] ) if receiver
        group_receiver ||= GROUP_OPERATORS.include? receiver.type
        group_receiver = false if receiver.children[1] == :[]
        if receiver.type == :int and !OPERATORS.flatten.include?(method)
          group_receiver = true
        end
        if not receiver.is_method? and receiver.children.last == :new
          group_receiver = true 
        end
      end

      if target
        group_target = target.type == :send &&
          op_index < operator_index( target.children[1] )
        group_target ||= GROUP_OPERATORS.include? target.type
      end

      put 'await ' if @ast.type == :await

      if method == :!
        parse s(:not, receiver)

      elsif method == :[]
        (group_receiver ? group(receiver) : parse(receiver))
        if \
          args.length == 1 and [:str, :sym].include? args.first.type and
          args.first.children.first.to_s =~ /^[a-zA-Z]\w*$/
        then
          put ".#{args.first.children.first}"
        else
          put '['; parse_all(*args, join: ', '); put ']'
        end

      elsif method == :[]=
        (group_receiver ? group(receiver) : parse(receiver))
        if \
          args.length == 2 and [:str, :sym].include? args.first.type and
          args.first.children.first.to_s =~ /^[a-zA-Z]\w*$/
        then
          put ".#{args.first.children.first} = "
        else
          put '['; parse_all(*args[0..-2], join: ', '); put '] = '
        end
        parse args[-1]

      elsif method == :** and not es2016
        put 'Math.pow('
        parse receiver
        put ', '
        parse args.first
        put ')'

      elsif [:-@, :+@, :~, '~'].include? method
        if \
          receiver.type == :send and
          receiver.children[1] == :+@ and
          Parser::AST::Node === receiver.children[0] and
          %i(class module).include? receiver.children[0].type
        then
          if receiver.children[0].type == :class
            parse receiver.children[0].updated(:class_extend)
          else
            mod = receiver.children[0]
            parse s(:assign, mod.children[0],
              mod.updated(nil, [nil, *mod.children[1..-1]]))
          end
        else
          put method.to_s[0]; parse receiver
        end

      elsif method == :=~
        parse args.first; put '.test('; parse receiver; put ')'

      elsif method == :!~
        put '!'; parse args.first; put '.test('; parse receiver; put ')'

      elsif method == :<< and args.length == 1 and @state == :statement
        parse receiver; put '.push('; parse args.first; put ')'

      elsif method == :<=>
        parse receiver; put ' < '; parse args.first; put ' ? -1 : '
        parse receiver; put ' > '; parse args.first; put ' ? 1 : 0'

      elsif OPERATORS.flatten.include?(method) and not LOGICAL.include?(method)
        (group_receiver ? group(receiver) : parse(receiver))

        if @comparison == :identity and [:==, :!=].include? method
          put " #{ method }= "
        else
          put " #{ method } "
        end

        (group_target ? group(target) : parse(target))

      elsif method =~ /=$/
        multi_assign_declarations if @state == :statement

        (group_receiver ? group(receiver) : parse(receiver))
        put "#{ '.' if receiver }#{ method.to_s.sub(/=$/, ' =') } "
        parse args.first, (@state == :method ? :method : :expression)

      elsif method == :new
        if receiver
          # map Ruby's "Regexp" to JavaScript's "Regexp"
          if receiver == s(:const, nil, :Regexp)
            receiver = s(:const, nil, :RegExp)
          end

          # allow a RegExp to be constructed from another RegExp
          if receiver == s(:const, nil, :RegExp)
            if args.first.type == :regexp
              opts = ''
              if args.first.children.last.children.length > 0
                opts = args.first.children.last.children.join
              end

              if args.length > 1
                opts += args.last.children.last
              end

              return parse s(:regexp, *args.first.children[0...-1],
                s(:regopt, *opts.split('').map(&:to_sym)))
            elsif args.first.type == :str
              if args.length == 2 and args[1].type == :str
                opts = args[1].children[0]
              else
                opts = ''
              end
              return parse s(:regexp, args.first,
                s(:regopt, *opts.each_char.map {|c| c}))
            end
          end

          put "new "; (group_receiver ? group(receiver) : parse(receiver))
          if ast.is_method?
            put '('; parse_all(*args, join: ', '); put ')'
          end
        elsif args.length == 1 and args.first.type == :send
          # accommodation for JavaScript like new syntax w/argument list
          parse s(:send, s(:const, *args.first.children[0..1]), :new,
            *args.first.children[2..-1]), @state
        elsif args.length == 1 and args.first.type == :const
          # accommodation for JavaScript like new syntax w/o argument list
          parse s(:attr, args.first, :new), @state
        elsif \
          args.length == 2 and [:send, :const].include? args.first.type and
          args.last.type == :def and args.last.children.first == nil
        then
          # accommodation for JavaScript like new syntax with block
          parse s(:send, s(:const, nil, args.first.children[1]), :new,
            *args.first.children[2..-1], args.last), @state
        else
          raise Error.new("use of JavaScript keyword new", @ast)
        end

      elsif method == :raise and receiver == nil
        if args.length == 1
          put 'throw '; parse args.first
        else
          put 'throw new '; parse args.first; put '('; parse args[1]; put ')'
        end

      elsif method == :typeof and receiver == nil
        put 'typeof '; parse args.first

      elsif ast.children[1] == :is_a? and receiver and args.length == 1
        put '('; parse receiver; put ' instanceof '; parse args.first; put ')'

      elsif ast.children[1] == :kind_of? and receiver and args.length == 1
        put '('; parse receiver; put ' instanceof '; parse args.first; put ')'

      elsif ast.children[1] == :instance_of? and receiver and args.length == 1
        put '('; parse s(:send, s(:attr, receiver, :constructor), :==, args.first); put ')'

      elsif receiver && receiver.to_a[1].eql?(:expect) && method.eql?(:to)
        (group_receiver ? group(receiver) : parse(receiver))
        put ".#{method}."
        if args.length <= 1
          parse_all(*args, join: ', ')
        else
          put args.first.to_a[1].to_s; put args.first.to_a.last.to_s.gsub(')',',');
          put "'#{args.last.to_a.first}'"; put ')'
        end

      elsif HELPER_METHODS.keys.include?(method)
        (group_receiver ? group(receiver) : parse(receiver))
        put HELPER_METHODS[method]; put '('
        args.each_with_index do |arg, index|
          if index == 1
            put "'', "
          end
          parse(arg);
          put(((args.size - 1) == index) ? ')' : ', ')
        end

      elsif SELENIUM_COMMANDS.keys.include?(method) && WEBDRIVER_HELPER_COMMANDS.keys.include?(args[0].to_a[1]) && args[0].to_a.last.to_s.include?('const')
        (group_receiver ? group(receiver) : parse(receiver))
        empty_command = WEBDRIVER_HELPER_COMMANDS[method].empty?
        command = WEBDRIVER_HELPER_COMMANDS[method]
        put "#{empty_command ? method : command }"
        put "("; put "'@#{args[0].to_a.last.to_a.last.to_s}'"; put ')'

      elsif SELENIUM_COMMANDS.keys.include?(method) && !args.join(',').include?('const')
        if !WEBDRIVER_HELPER_COMMANDS.keys.include?(method) && !receiver.nil?
          empty_command = SELENIUM_COMMANDS[method].empty?
          command = SELENIUM_COMMANDS[method]
          put "#{empty_command ? method : command }"
          put "("; parse(receiver); put '.getId()' ;
        else
          (group_receiver ? group(receiver) : parse(receiver))
          empty_command = SELENIUM_COMMANDS[method].empty?
          command = SELENIUM_COMMANDS[method]
          put "#{empty_command ? method : command }"
          put "("; put "#{args[0].to_a.first.to_s.gsub(/(?!^)_[a-z0-9]/) {|match| match[1].upcase}}.getId()"
          args.shift
        end
        if args.length > 0
          compact { put ', '; parse_all(*args, join: ",#@ws"); sput ')';}
        else
          put ')'
        end

      elsif method.to_s.eql?('get_child_element') || method.to_s.eql?('get_child_elements') || args.join(',').include?('get_child_element')
        (group_receiver ? group(receiver) : parse(receiver))
        if !args.join(',').include?('get_child_element')
          command = WEBDRIVER_HELPER_COMMANDS[method]
          put command
        else
          put SELENIUM_COMMANDS[method]
        end
        if args.length <= 1
          put "("; parse_all(*args, join: ', '); put ')';
        else
          compact { puts "("; put "#{args[0].to_a.last.to_s.gsub(/(?!^)_[a-z0-9]/) {|match| match[1].upcase}}.getId(), "; 
          put "this.elements.#{args[1].to_a.last.to_s}.locateStrategy, "; put "this.elements.#{args[1].to_a.last.to_s}.selector"; sput ')';}
        end

      elsif WEBDRIVER_HELPER_COMMANDS.keys.include?(method)
        (group_receiver ? group(receiver) : parse(receiver))
        locator_present = WEBDRIVER_HELPER_COMMANDS[method].include?('<locator>') 
        empty_command = WEBDRIVER_HELPER_COMMANDS[method].empty?
        command = locator_present ? WEBDRIVER_HELPER_COMMANDS[method].gsub('<locator>', "'@#{args.first.children.last.to_s}'") : WEBDRIVER_HELPER_COMMANDS[method]
        put "#{empty_command ? method : command }"
        if !locator_present
          if args.length <= 1
            if method.to_s.eql?('env_variable') 
              put args.first.children.last.to_s
            else
              put "("; parse_all(*args, join: ', '); put ')';
            end
          else
            compact { puts "("; parse_all(*args, join: ",#@ws"); sput ')';}
          end
        end

      elsif METHODS.keys.include?(method) || METHODS.keys.include?(method.to_sym)
        (group_receiver ? group(receiver) : parse(receiver))
        if(method.to_s.eql?('parse'))
          parse_all(*args, join: ', ')
        else
          put METHODS[method.to_sym]
          if method.to_s.include?('eql')
            parse_all(*args, join: ', ')
          elsif args.length <= 1
            put "("; parse_all(*args, join: ', '); put ')'
          else
            compact { puts "("; parse_all(*args, join: ",#@ws"); sput ')' }
          end
        end

      elsif ASSERT_COMMANDS.keys.include?(method)
        empty_command = ASSERT_COMMANDS[method].empty?
        put "#{empty_command ? method : ASSERT_COMMANDS[method] }"
        if args.length <= 1
          put "("; parse_all(*args, join: ', '); put ')';
        else
          compact { puts "("; parse_all(*args, join: ",#@ws"); sput ')';}
        end

      else
        if method == :bind and receiver&.type == :send
          if receiver.children.length == 2 and receiver.children.first == nil
            receiver = receiver.updated(:attr) # prevent autobind
          end
        end

        if not ast.is_method? and ast.type != :send!
          if receiver
            (group_receiver ? group(receiver) : parse(receiver))
            put ".#{ method }"
          elsif ast.type == :attr
            put method
          else
            parse ast.updated(:lvasgn, [method]), @state
          end
        elsif args.any? {|arg| arg.type == :splat} and not es2015
          parse s(:send, s(:attr, receiver, method), :apply,
            (receiver || s(:nil)), s(:array, *args))
        else
          (group_receiver ? group(receiver) : parse(receiver))
          put "#{ '.' if receiver && method}#{ method }"

          if args.length <= 1
            put "("; parse_all(*args, join: ', '); put ')'
          else
            compact { puts "("; parse_all(*args, join: ",#@ws"); sput ')' }
          end
        end

        if autobind and not ast.is_method? and ast.type != :attr
          if @state == :statement
            put '()'
          else
            put '.bind('; parse(autobind); put ')'
          end
        end
      end
    end

    handle :csend do |receiver, method, *args|
      if es2020

        # optional chaining
        parse receiver
        put "?."
        if method == :[]
          put '['
          args.each {|arg| parse arg}
          put ']'
        else
          put method.to_s
          put '(' if @ast.is_method?
          args.each {|arg| parse arg}
          put ')' if @ast.is_method?
        end

      else

        node = @ast

        # collect up chain of conditional sends
        stack = []
        while node.children.first.type == :csend
          stack << node
          node = node.children.first
        end

        # conditionally evaluate most nested expression
        expr = node.updated(:send)
        result = s(:and, node.children.first, expr)

        # build up chain of conditional evaluations
        until stack.empty?
          node = stack.pop
          expr = node.updated(:send, [expr, *node.children[1..-1]])
          result = s(:and, result, expr)
        end

        parse result
      end
    end

    handle :splat do |expr|
       put '...'
       parse expr
    end

    # do string concatenation when possible
    def collapse_strings(node)
      left = node.children[0]
      return node unless left
      right = node.children[2]

      # recursively evaluate left hand side
      if \
        left.type == :send and left.children.length == 3 and
        left.children[1] == :+
      then
        left = collapse_strings(left)
      end

      # recursively evaluate right hand side
      if \
        right.type == :send and right.children.length == 3 and
        right.children[1] == :+
      then
        right = collapse_strings(right)
      end

      # if left and right are both strings, perform concatenation
      if [:dstr, :str].include? left.type and [:dstr, :str].include? right.type
        if left.type == :str and right.type == :str
          return left.updated nil,
            [left.children.first + right.children.first]
        else
          left = s(:dstr, left) if left.type == :str
          right = s(:dstr, right) if right.type == :str
          return left.updated(nil, left.children + right.children)
        end
      end

      # if left and right are unchanged, return original node; otherwise
      # return node modified to include new left and/or right hand sides.
      if left == node.children[0] and right == node.children[2]
        return node
      else
        return node.updated(nil, [left, :+, right])
      end
    end

    def range_to_array(node)
      start, finish = node.children
      if start.type == :int and start.children.first == 0
        # Ranges which start from 0 can be achieved with more simpler code
        if finish.type == :int
          # output cleaner code if we know the value already
          length = finish.children.first + (node.type == :irange ? 1 : 0)
        else
          # If this is variable we need to fix indexing by 1 in js
          length = "#{finish.children.last}" + (node.type == :irange ? "+1" : "")
        end

        if es2015
          return put "[...Array(#{length}).keys()]"
        else
          return put "Array.apply(null, {length: #{length}}).map(Function.call, Number)"
        end
      else
        # Use .compact because the first argument is nil with variables
        # This way the first value is always set
        start_value = start.children.compact.first
        finish_value = finish.children.compact.first
        if start.type == :int and finish.type == :int
          length = finish_value - start_value + (node.type == :irange ? 1 : 0)
        else
          length = "(#{finish_value}-#{start_value}" + (node.type == :irange ? "+1" : "") + ")"
        end

        # Avoid of using same variables in the map as used in the irange or elsewhere in this code
        # Ruby2js only allows dollar sign in beginning of variable so i$ is safe
        if @vars.include? :idx or start_value == :idx or finish_value == :idx
          index_var = 'i$'
        else
          index_var = 'idx'
        end

        if es2015
          # Use _ because it's normal convention in JS for variable which is not used at all
          if @vars.include? :_ or start_value == :_ or finish_value == :_
            blank = '_$'
          else
            blank = '_'
          end

          return put "Array.from({length: #{length}}, (#{blank}, #{index_var}) => #{index_var}+#{start_value})"
        else
          return put "Array.apply(null, {length: #{length}}).map(Function.call, Number).map(function (#{index_var}) { return #{index_var}+#{start_value} })"
        end
      end
    end
  end
end
