# tracematch-rb

An incomplete Trace Mathing implementation in Ruby

## Usage

Create target files named `target-def.rb` and `target-code.rb`.

```
def f
  puts "called f"
end

def g
  puts "called g"
end
```

```
g
f
g
f
g
```

And write tracematch.

```
require 'tracematch.rb'

tm = Tracematch.tracematch do
  sym(:f, :before)
    .call(:f, [_.._])

  sym(:g, :after)
    .call(:g, [_.._])

  match("f g") do
    puts "fg!"
  end
end

tm.run(File.read("./target-def.rb"), File.read("./target-code.rb"))
```

Then, run tracematch.

```
$ ruby tm.rb
called g
called f
called g
fg!
called f
called g
fg!
```
