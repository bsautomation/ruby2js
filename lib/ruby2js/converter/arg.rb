module Ruby2JS
  class Converter

    # (arg :a)
    # (blockarg :b)

    # NOTE: process_all appends a nil child for unknown reasons

    handle :arg, :blockarg do |arg, unknown=nil|
      raise Error.new("argument #{ unknown.inspect }", @ast) if unknown
      put arg.to_s.gsub(/(?!^)_[a-z0-9]/) {|match| match[1].upcase}
    end

    # (shadowarg :a)

    handle :shadowarg do |arg, unknown=nil|
      raise Error.new("argument #{ unknown.inspect }", @ast) if unknown
      nil
    end
  end
end
