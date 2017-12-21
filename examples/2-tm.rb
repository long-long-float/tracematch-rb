require './tracematch.rb'

tm = Tracematch.tracematch(r: :Reader) do
  sym(:close, :after)
    .call(:Reader, :close, [])
    .target(:r)
  sym(:read, :before)
    .call(:Reader, :read, [])
    .target(:r)

  match("close read") do
    raise "read after close"
  end
end

tm.run(File.read("./2-target-def.rb"), File.read("./2-target-code.rb"))
