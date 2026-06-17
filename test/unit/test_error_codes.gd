extends GutTest
## Checks on the player-facing error catalogue — the small fixed table the error screen reads.
## It covers the two guarantees a caller leans on: every shipped code has a stable badge and a
## headline, and an unknown code still formats rather than crashing the one screen meant to explain
## a failure. No display, no networking — `ErrorOverlay` owns those; this is the whole of the data.


func test_label_formats_a_code_as_a_badge() -> void:
	assert_eq(ErrorCode.label(ErrorCode.UNREACHABLE), "E-1003")
	assert_eq(ErrorCode.label(ErrorCode.CANT_HOST), "E-1001")


func test_every_shipped_code_has_a_headline() -> void:
	for code in [
		ErrorCode.CANT_HOST,
		ErrorCode.CANT_CONNECT,
		ErrorCode.UNREACHABLE,
		ErrorCode.REFUSED,
		ErrorCode.LOST,
	]:
		assert_ne(ErrorCode.title(code), "", "code %d has a headline" % code)
		assert_ne(ErrorCode.title(code), "Something went wrong", "code %d is not the fallback" % code)


func test_an_unknown_code_still_formats() -> void:
	# A code not in the table must never crash the error screen — the one screen that explains a
	# failure should always have a badge and a line, even for a number nobody catalogued.
	assert_eq(ErrorCode.label(9999), "E-9999", "an unlisted code still reads as a badge")
	assert_eq(ErrorCode.title(9999), "Something went wrong", "an unlisted code gets a generic line")
