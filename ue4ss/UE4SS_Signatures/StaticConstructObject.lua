-- StaticConstructObject_Internal AOB for Longvinter (UE 5.7.2)
-- Candidate function at 0x1415a7560: 399 bytes, 14,664 xrefs, security-cookie protected
-- Identified via Ghidra static analysis as the most likely SCOI candidate
-- Function prologue:
--   PUSH RBX
--   PUSH RSI
--   PUSH R12 R14 R15
--   SUB RSP, 0x290
--   MOV RAX, [RIP+__security_cookie]
--   XOR RAX, RSP
--   MOV [RSP+0x280], RAX

function Register()
    -- 16-byte prologue: 40 53 56 41 54 41 56 41 57 48 81 EC 90 02 00 00
    return "4 0/5 3/5 6/4 1/5 4/4 1/5 6/4 1/5 7/4 8/8 1/E C/9 0/0 2/0 0/0 0"
end

function OnMatchFound(MatchAddress)
    -- Pattern is the function entry itself; return as-is
    return MatchAddress
end
