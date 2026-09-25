# Demo data: ~20 fictional studios across every subscription state, built through the real
# services over 70 simulated days. See Demo::Seed for the calendar.
summary = Demo::Seed.call
puts "Seeded demo data: #{summary.inspect}"
