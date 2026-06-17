class_name ErrorCode
extends RefCounted
## The client's catalogue of player-facing failure codes. Each failure that would otherwise grey
## the screen or quit without a word gets a stable number, shown on the error screen so a bug
## report can name what broke. The numbers never change once shipped (a player may quote one), so
## a new failure takes the next free number rather than reusing an old one.
##
## Pure data: a code maps to a headline (what went wrong, in plain words). The specific detail —
## which address, which port, the raw reason — is passed alongside the code at the call site, so
## this stays a small fixed table the error overlay (and any future log) can read.

## Could not start hosting — the listen-server socket would not open (usually the port is taken).
const CANT_HOST := 1001
## Could not start the outgoing connection — the address was malformed or the socket would not open.
const CANT_CONNECT := 1002
## The attempt reached no one — no server answered at the address (host down, or wrong address).
const UNREACHABLE := 1003
## The server answered but refused us — today only a protocol-version mismatch (different builds).
const REFUSED := 1004
## The connection dropped after we had joined — the server closed, or the link died mid-match.
const LOST := 1005

const _TITLES := {
	CANT_HOST: "Could not host the match",
	CANT_CONNECT: "Could not start the connection",
	UNREACHABLE: "Could not reach the server",
	REFUSED: "The server refused the connection",
	LOST: "Lost the connection to the server",
}


## The code as the badge the player sees and quotes — "E-1003". An unknown code still formats, so a
## caller can never crash the error screen by passing a number that is not in the table.
static func label(code: int) -> String:
	return "E-%d" % code


## The player-facing headline for a code, or a generic line for an unknown code so the screen always
## has something to say.
static func title(code: int) -> String:
	return _TITLES.get(code, "Something went wrong")
