module Ruby2JS
  class Converter

    # (lvar :a)
    # (gvar :$a)

    handle :lvar, :gvar do |var|
      if var == :$!
        put '$EXCEPTION'
      else
        put var.to_s.gsub(/(?!^)_[a-z0-9]/) {|match| match[1].upcase}
      end
    end
  end
end
