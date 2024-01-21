# # Dispatcher
#
# Dispatch `call(method, *args)` to `@target.on_<name>(*args)` or `@on[method].call(*args)`
# where <name> is a cleaned up string representation of method, so that:
#
#   dispatch.(X11::Form::MotionNotify, arg1, arg2)
#
# Becomes:
#
#   @target.on_motion_notify(arg1, arg2)
#
class Dispatcher
  def initialize(target=nil)
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

    
