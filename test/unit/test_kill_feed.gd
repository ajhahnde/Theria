extends GutTest
## Behavioural checks on the kill feed — the top-right takedown stack. They verify a pushed
## line lands on the feed and that the feed caps its length, dropping the oldest. Expiry by
## timer is time-driven and not asserted here; the cap and the push are the whole of the
## list logic the driver depends on.


func _feed() -> KillFeed:
	var feed := KillFeed.new()
	add_child_autoqfree(feed)
	return feed


func test_push_adds_a_line() -> void:
	var feed := _feed()
	feed.push("Lion was slain", Color.WHITE)
	assert_eq(feed.get_child_count(), 1, "a pushed kill lands on the feed")


func test_push_caps_the_feed_length() -> void:
	var feed := _feed()
	for i in KillFeed.MAX_ENTRIES + 3:
		feed.push("kill %d" % i, Color.WHITE)
	assert_eq(feed.get_child_count(), KillFeed.MAX_ENTRIES, "the feed drops the oldest past the cap")


func test_newest_line_sits_on_top() -> void:
	var feed := _feed()
	feed.push("first", Color.WHITE)
	feed.push("second", Color.WHITE)
	assert_eq((feed.get_child(0) as Label).text, "second", "the newest line is on top")
