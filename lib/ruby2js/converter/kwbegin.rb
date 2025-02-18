module Ruby2JS
  class Converter

    # (rescue
    #   (send nil :a)
    #     (resbody nil nil
    #       (send nil :b)) nil)
    handle :rescue do |*statements|
      parse s(:kwbegin, s(:rescue, *statements)), @state
    end

    # (kwbegin
    #   (ensure
    #     (rescue
    #       (send nil :a)
    #       (resbody nil nil
    #         (send nil :b)) nil)
    #    (send nil :c)))

    handle :kwbegin do |*children|
      block = children.first

      if @state == :expression
        parse s(:send, s(:block, s(:send, nil, :proc), s(:args),
          s(:begin, s(:autoreturn, *children))), :[])
        return
      end

      if block&.type == :ensure
        block, finally = block.children
      else
        finally = nil
      end

      if block and block.type == :rescue
        body, *recovers, otherwise = block.children
        raise Error.new("block else", @ast) if otherwise

        var = recovers.first.children[1]

        if recovers.any? {|recover| recover.children[1] != var}
          raise Error.new( 
            "multiple recovers with different exception variables", @ast)
        end

        if recovers[0..-2].any? {|recover| not recover.children[0]}
          raise Error.new( 
            "additional recovers after catchall", @ast)
        end
      else
        body = block
      end

      if not recovers and not finally
        return scope s(:begin, *children)
      end

      puts "try {"; scope body; sput '}'

      if recovers

        if recovers.length == 1 and not recovers.first.children.first
          # find reference to exception ($!)
          walk = proc do |ast|
            result = ast if ast.type === :gvar and ast.children.first == :$!
            ast.children.each do |child|
              result ||= walk[child] if child.is_a? Parser::AST::Node
            end
            result
          end

          # single catch with no exception named
          if es2019 and not var and not walk[@ast]
            puts " catch {"
          else
            var ||= s(:gvar, :$EXCEPTION)
            put " catch ("; parse var; puts ") {"
          end
          scope recovers.first.children.last; sput '}'
        else
          var ||= s(:gvar, :$EXCEPTION)
          put " catch ("; parse var; puts ') {'

          first = true
          recovers.each do |recover|
            exceptions, var, recovery = recover.children
            var ||= s(:gvar, :$EXCEPTION)

            scope recovery; puts ''
          end

          put '}'
        end
      end

      (puts ' finally {'; scope finally; sput '}') if finally
    end
  end
end
