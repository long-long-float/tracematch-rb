require './tracematch.rb'

tm = Tracematch.tracematch do
  sym(:f, :before)
    .call(:f, [_.._])

  sym(:g, :after)
    .call(:g, [_.._])

  match("f g") do
    puts "fg!"
  end
end

tm.run(File.read("./1-target-def.rb"), File.read("./1-target-code.rb"))
