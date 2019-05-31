let rec a =
  let x = b in
  0 :: x
and b =
  (* let y = a in *)
  1 :: a
