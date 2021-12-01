module Ruby2JS
  class Converter

    # (const nil :C)

    handle :const do |receiver, name|
      # resolve anonymous receivers against rbstack
      receiver ||= @rbstack.map {|rb| rb[name]}.compact.last

      if receiver
        if Parser::AST::Node === receiver and receiver.type == :cbase
          put 'Function("return this")().'
        else
          parse receiver
          put '.'
        end

      end
      
      if name.to_s.eql?('ENV')
        put "browser.globals"
      else
        put "'@#{name}'"
      end
    end
  end
end
