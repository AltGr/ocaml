let rec a =
  let x = b; 3 in
  let y = x; b
  in
  let rec z = 1 :: y
  and u = 2 :: z
  in u
and b = 4 :: a
