class TypeDispatcher
  def initialize(target)
    @target = target
    @on = {}
  end

  def name_to_event(ob)
    name = ob.to_s.split("::").last.split(/([A-Z][a-z]+)/).join("_").downcase
    "on_#{name}".gsub(/__+/,"_").to_sym
  end

  def on(event, &block)
    @on[name_to_event(event)] = block
  end

  def call(ob, *args)
    sym = name_to_event(ob)

    if @on[sym]
      @on[sym].(*args)
    elsif @target.respond_to?(sym)
      arity = @target.method(sym).arity
      @target.send(sym, *args[0...arity])
    end
  end
end

    
