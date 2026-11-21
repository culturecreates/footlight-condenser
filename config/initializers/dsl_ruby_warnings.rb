# Installed once. Only an active DSL evaluation can opt into filtering.
Warning.singleton_class.prepend(Module.new do
  def warn(message, **options)
    context = Thread.current[:footlight_dsl_ruby_warnings]
    return super unless context&.count_if_repeated_definition(message)

    nil
  end
end)
