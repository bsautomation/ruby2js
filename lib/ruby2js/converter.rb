require 'ruby2js/serializer'

module Ruby2JS
  class Error < NotImplementedError
    def initialize(message, ast)
      if ast.loc
        message += ' at ' + ast.loc.expression.source_buffer.name.to_s
        message += ':' + ast.loc.expression.line.inspect
        message += ':' + ast.loc.expression.column.to_s
      end
      super(message)
    end
  end

  class Converter < Serializer
    attr_accessor :ast

    LOGICAL   = :and, :not, :or
    OPERATORS = [:[], :[]=], [:not, :!], [:**], [:*, :/, :%], [:+, :-], 
      [:>>, :<<], [:&], [:^, :|], [:<=, :<, :>, :>=],
      [:==, :!=, :===, :"!==", :=~, :!~], [:and, :or]
    
    INVERT_OP = {
      :<  => :>=,
      :<= => :>,
      :== => :!=,
      :!= => :==,
      :>  => :<=,
      :>= => :<,
      :=== => :'!=='
    }

    METHODS= {
      'include': '.includes',
      'size': '.length'
    }

    GROUP_OPERATORS = [:begin, :dstr, :dsym, :and, :or, :casgn, :if]

    VASGN = [:cvasgn, :ivasgn, :gvasgn, :lvasgn]

    ASSERT_COMMANDS = {
      :assert_empty => 'assert',
      :assert_json => '',
      :assert_not_contains => 'assert.notInclude',
      :assert_greater_than_equal_to => 'assert.isAbove',
      :assert_true => 'assert.isTrue',
      :assert_false => 'assert.isNotTrue',
      :assert_json_array => '',
      :assert_float_equals => '',
      :assert_nil => 'assert.exists',
      :assert_not_nil => 'assert.notExists',
      :assert_include => 'assert.include',
      :assert_equals => 'assert.equal',
      :assert_not_include => 'assert.notInclude',
      :assert_less_than_equal_to => 'assert.isBelow',
      :assert_equals_with_or => '',
    }

    SELENIUM_COMMANDS= {
      :get_element_or_exception => '',
      :visible_element => 'await this.isVisible',
      :get_elements => 'await this.elements',
      :wait_for_element_visibility => 'await this.waitForElementVisible',
      :element_displayed? => 'await this.isVisible',
      :wait_for_element => 'await this.waitForElementPresent',
      :get_parent_element => '',
      :get_child_element => 'await this.findElement',
      :get_child_elements => 'await this.findElements',
      :get_image_natural_width => '',
      :page_refresh => 'await browser.refresh',
      :element_click_js => 'await this.click',
      :element_click => 'await this.click',
      :element_from_element_or_selector => '',
      :session_id => 'browser.sessionId',
      :page_scroll_down => '',
      :element_displayed_js? => 'await this.isVisible',
      :element_not_displayed? => '!await this.isVisible',
      :element_not_displayed_condition => 'await this.waitForElementNotVisible',
      :number_of_elements_displayed => '',
      :element_enabled? => 'await this.isEnabled',
      :wait_for_condition => '',
      :hover_to_element => 'await webDriverHelper.moveToElementCustom',
      :alert_text => 'await this.getAlertText',
      :alert_exist? => '',
      :wait_for_alert => '',
      :wait_for_new_window => '',
      :window_handles => 'await browser.windowHandles',
      :accept_alert => 'await this.acceptAlert',
      :dismiss_alert => 'await this.dismissAlert',
      :get_current_page_url => 'await webDriverHelper.getCurrentPageUrl',
      :visit_url => 'await browser.url',
      :visit_url_in_new_tab => '',
      :new_tab => 'await browser.openNewWindow',
      :switch_to_window => 'await browser.switchWindow',
      :page_title => 'await browser.getTitle',
      :page_url_scheme_https? => '',
      :checkbox_selected? => 'await this.isSelected',
      :click_checkbox => 'await this.click',
      :uncheck_checkbox => 'if(await this.isSelected) await this.click',
      :element_attribute => 'await this.getAttribute',
      :set_element_attribute => '',
      :element_style => 'await this.getCssProperty',
      :press_keys => '',
      :select_all_using_keyboard => '',
      :key_down => '',
      :key_up => '',
      :paste_using_keyboard => '',
      :send_session_id => '',
      :move_to_element => 'await webDriverHelper.moveToElementCustom',
      :get_scrollY_val => '',
      :open_link_in_new_tab => '',
      :add_cookie => 'await browser.setCookie',
      :delete_all_cookies => 'await browser.deleteCookies',
      :move_to_element_and_click => 'await this.click',
      :move_by_and_click => 'await this.click',
      :scroll_to => '',
      :scroll_to_element_and_click => 'await this.click',
      :select_by_text => '',
      :element_drag_and_drop_by => '',
      :get_element_location => 'await this.getLocation',
      :window_width => '',
      :window_height => '',
      :resize_browser => '',
      :resize_window => 'await browser.resizeWindow',
      :mouse_scroll => '',
      :close_current_window => 'await browser.closeWindow',
      :mobile_view? => '',
      :drag_and_drop_from_on => '',
      :element_text => 'await this.getText',
      :element_value => 'await this.getAttribute(<locator>, "value")',
      :switch_frame => 'await frame',
      :switch_to_default => '',
      :get_console_logs => 'await browser.getLog',
      :get_elements_text_list => '',
      :clear_text_field => 'await this.clearValue',
      :send_keys_js => 'await sendKeys',
      :select_from_dropdown => '',
      :start_concurrent_driver => '',
      :start_n_concurrent_driver => '',
      :quit_drivers => '',
      :page_loaded? => '',
      :wait_for_element_with_page_refresh => '',
      :navigate_to_previous_page => 'await browser.back',
      :new_window_visible? => '',
      :experiment_value => '',
      :driver_network_logs => '',
      :get_element_height_and_width => '',
      :file_downloaded? => '',
      :element_disabled? => ' await this.isVisible',
      :scroll_up_till_element_visible => '',
      :scroll_up => '',
      :wait_without_implicit_wait => '',
      :free_trail_device_expt => '',
      :free_app_live_user? => '',
      :user_with_even_id? => '',
      :cookie_data => 'await browser.getCookie',
      :allocate_experiment => '',
      :set_current_browser => '',
      :is_element_stale => '',
      :allocate_experiment_new_framework => '',
      :allocate_experiment_group => '',
      :find_element_and_send_keys => '',
      :catch_stale_exception => '',
      :get_element => 'await this.findElement',
      :send_keys => 'await this.sendKeys',
      :cancel_url_onboarding_modal => '',
      :wait_for_page_load => '',
      :set_user_property => '',
      :execute_script => '',
      :catch_exception => '',
      :catch_exception_and_retry => '',
      :selectors_from_page_objects => '',
      :send_keys_for_ie => '',
      :percy_screenshot => '',
      :accept_cookie_notification => '',
      :set_cookie_value => '',
      :scroll_down_till_element_is_visible => '',
      :click_element_and_select_value => '',
      :send_devtools_cmd => '',
      :sleep => 'await browser.pause',
    }

    attr_accessor :binding, :ivars, :namespace

    def initialize( ast, comments, vars = {} )
      super()

      @ast, @comments, @vars = ast, comments, vars.dup
      @varstack = []
      @scope = ast
      @inner = nil
      @rbstack = []
      @next_token = :return

      @handlers = {}
      @@handlers.each do |name|
        @handlers[name] = method("on_#{name}")
      end

      @state = nil
      @block_this = nil
      @block_depth = nil
      @prop = nil
      @instance_method = nil
      @prototype = nil
      @class_parent = nil
      @class_name = nil
      @jsx = false
      @autobind = true

      @eslevel = :es5
      @strict = false
      @comparison = :equality
      @or = :logical
      @underscored_private = true
      @redoable = false
    end

    def width=(width)
      @width = width
    end

    def convert
      scope @ast 

      if @strict
        if @sep == '; '
          @lines.first.unshift "\"use strict\"#@sep"
        else
          @lines.unshift Line.new('"use strict";')
        end
      end
    end

    def operator_index op
      OPERATORS.index( OPERATORS.find{ |el| el.include? op } ) || -1
    end
    
    # define a new scope; primarily determines what variables are visible and deals with hoisting of
    # declarations
    def scope( ast, args=nil )
      scope, @scope = @scope, ast
      inner, @inner = @inner, nil 
      mark = output_location
      @varstack.push @vars
      @vars = args if args
      @vars = Hash[@vars.map {|key, value| [key, true]}]

      parse( ast, :statement )

      # retroactively add a declaration for 'pending' variables
      vars = @vars.select {|key, value| value == :pending}.keys
      unless vars.empty?
        insert mark, "#{es2015 ? 'let' : 'var'} #{vars.join(', ')}#{@sep}"
        vars.each {|var| @vars[var] = true}
      end
    ensure
      @vars = @varstack.pop
      @scope = scope
      @inner = inner
    end

    # handle the oddity where javascript considers there to be a scope (e.g. the body of an if statement),
    # whereas Ruby does not.
    def jscope( ast, args=nil )
      @varstack.push @vars
      @vars = args if args
      @vars = Hash[@vars.map {|key, value| [key, true]}]

      parse( ast, :statement )
    ensure
      pending = @vars.select {|key, value| value == :pending}
      @vars = @varstack.pop
      @vars.merge! pending
    end

    def s(type, *args)
      Parser::AST::Node.new(type, args)
    end

    attr_accessor :strict, :eslevel, :module_type, :comparison, :or, :underscored_private

    def es2015
      @eslevel >= 2015
    end

    def es2016
      @eslevel >= 2016
    end

    def es2017
      @eslevel >= 2017
    end

    def es2018
      @eslevel >= 2018
    end

    def es2019
      @eslevel >= 2019
    end

    def es2020
      @eslevel >= 2020
    end

    def es2021
      @eslevel >= 2021
    end

    def es2022
      @eslevel >= 2022
    end

    @@handlers = []
    def self.handle(*types, &block)
      types.each do |type| 
        define_method("on_#{type}", block)
        @@handlers << type
      end
    end

    # extract comments that either precede or are included in the node.
    # remove from the list this node may appear later in the tree.
    def comments(ast)
      if ast.loc and ast.loc.respond_to? :expression
        expression = ast.loc.expression

        list = @comments[ast].select do |comment|
          expression.source_buffer == comment.loc.expression.source_buffer and
          comment.loc.expression.begin_pos < expression.end_pos
        end
      else
        list = @comments[ast]
      end

      @comments[ast] -= list

      list.map do |comment|
        if comment.text.start_with? '=begin'
          if comment.text.include? '*/'
            comment.text.sub(/\A=begin/, '').sub(/^=end\Z/, '').gsub(/^/, '//')
          else
            comment.text.sub(/\A=begin/, '/*').sub(/^=end\Z/, '*/')
          end
        else
          comment.text.sub(/^#/, '//') + "\n"
        end
      end
    end

    def parse(ast, state=:expression)
      oldstate, @state = @state, state
      oldast, @ast = @ast, ast
      return unless ast

      handler = @handlers[ast.type]

      unless handler
        raise Error.new("unknown AST type #{ ast.type }", ast)
      end

      if state == :statement and not @comments[ast].empty?
        comments(ast).each {|comment| puts comment.chomp}
      end

      handler.call(*ast.children)
    ensure
      @ast = oldast
      @state = oldstate
    end

    def parse_all(*args)
      @options = (Hash === args.last) ? args.pop : {}
      sep = @options[:join].to_s
      state = @options[:state] || :expression

      index = 0
      args.each do |arg|
        put sep unless index == 0
        parse arg, state
        index += 1 unless arg == s(:begin)
      end
    end
    
    def group( ast )
      if [:dstr, :dsym].include? ast.type and es2015
        parse ast
      else
        put '('; parse ast; put ')'
      end
    end

    def redoable(block)
      save_redoable = @redoable

      has_redo = proc do |node|
        node.children.any? do |child|
          next false unless child.is_a? Parser::AST::Node
          next true if child.type == :redo
          next false if %i[for while while_post until until_post].include? child.type
          has_redo[child]
        end
      end

      @redoable = has_redo[@ast]

      if @redoable
        put es2015 ? 'let ' : 'var '
        put "redo$#@sep"
        puts 'do {'
        put "redo$ = false#@sep"
        scope block
        put "#@nl} while(redo$)"
      else
        scope block
      end
    ensure
      @redoable = save_redoable
    end

    def timestamp(file)
      super

      return unless file

      walk = proc do |ast|
        if ast.loc and ast.loc.expression
          filename = ast.loc.expression.source_buffer.name
          if filename and not filename.empty?
            @timestamps[filename] ||= File.mtime(filename) rescue nil
          end
        end

        ast.children.each do |child|
          walk[child] if child.is_a? Parser::AST::Node
        end
      end

      walk[@ast] if @ast
    end
  end
end

module Parser
  module AST
    class Node
      def is_method?
        return false if type == :attr
        return true if type == :call
        return true unless loc

        if loc.respond_to? :selector
          return true if children.length > 2
          selector = loc.selector
        elsif type == :defs
          return true if children[1] =~ /[!?]$/
          return true if children[2].children.length > 0
          selector = loc.name
        elsif type == :def
          return true if children[0] =~ /[!?]$/
          return true if children[1].children.length > 0
          selector = loc.name
        end

        return true unless selector and selector.source_buffer
        selector.source_buffer.source[selector.end_pos] == '('
      end
    end
  end
end

# see https://github.com/whitequark/parser/blob/master/doc/AST_FORMAT.md

require 'ruby2js/converter/arg'
require 'ruby2js/converter/args'
require 'ruby2js/converter/array'
require 'ruby2js/converter/assign'
require 'ruby2js/converter/begin'
require 'ruby2js/converter/block'
require 'ruby2js/converter/blockpass'
require 'ruby2js/converter/boolean'
require 'ruby2js/converter/break'
require 'ruby2js/converter/case'
require 'ruby2js/converter/casgn'
require 'ruby2js/converter/class'
require 'ruby2js/converter/class2'
require 'ruby2js/converter/const'
require 'ruby2js/converter/cvar'
require 'ruby2js/converter/cvasgn'
require 'ruby2js/converter/def'
require 'ruby2js/converter/defs'
require 'ruby2js/converter/defined'
require 'ruby2js/converter/dstr'
require 'ruby2js/converter/fileline'
require 'ruby2js/converter/for'
require 'ruby2js/converter/hash'
require 'ruby2js/converter/hide'
require 'ruby2js/converter/if'
require 'ruby2js/converter/in'
require 'ruby2js/converter/import'
require 'ruby2js/converter/ivar'
require 'ruby2js/converter/ivasgn'
require 'ruby2js/converter/kwbegin'
require 'ruby2js/converter/literal'
require 'ruby2js/converter/logical'
require 'ruby2js/converter/masgn'
require 'ruby2js/converter/match'
require 'ruby2js/converter/module'
require 'ruby2js/converter/next'
require 'ruby2js/converter/nil'
require 'ruby2js/converter/nthref'
require 'ruby2js/converter/opasgn'
require 'ruby2js/converter/prototype'
require 'ruby2js/converter/redo'
require 'ruby2js/converter/regexp'
require 'ruby2js/converter/return'
require 'ruby2js/converter/self'
require 'ruby2js/converter/send'
require 'ruby2js/converter/super'
require 'ruby2js/converter/sym'
require 'ruby2js/converter/taglit'
require 'ruby2js/converter/undef'
require 'ruby2js/converter/until'
require 'ruby2js/converter/untilpost'
require 'ruby2js/converter/var'
require 'ruby2js/converter/vasgn'
require 'ruby2js/converter/while'
require 'ruby2js/converter/whilepost'
require 'ruby2js/converter/xstr'
require 'ruby2js/converter/xnode'
require 'ruby2js/converter/yield'
