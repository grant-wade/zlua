-- min-stack: 1048576
-- outcome: interrupted
-- max-instructions: none
-- interrupt-ms: 100
-- latency-ms: 2000
return ("a"):rep(32):find(("a-"):rep(12) .. "b")
