#!/bin/sh

test_description="Test bundle-uri bundle_uri_parse_line()"

TEST_NO_CREATE_REPO=1
. ./test-lib.sh

test_expect_success 'bundle_uri_parse_line() just URIs' '
	cat >in <<-\EOF &&
	http://example.com/bundle.bdl
	https://example.com/bundle.bdl
	file:///usr/share/git/bundle.bdl
	EOF

	# For the simple case
	cp in expect &&

	test-tool bundle-uri parse <in >actual 2>err &&
	test_must_be_empty err &&
	test_cmp expect actual 
'

test_expect_success 'bundle_uri_parse_line() with attributes' '
	cat >in <<-\EOF &&
	http://example.com/bundle1.bdl attr
	http://example.com/bundle2.bdl ibute
	EOF


	cat >expect <<-\EOF &&
	http://example.com/bundle1.bdl [attr: attr]
	http://example.com/bundle2.bdl [attr: ibute]
	EOF

	test-tool bundle-uri parse <in >actual 2>err &&
	test_must_be_empty err &&
	test_cmp expect actual
'

test_expect_success 'bundle_uri_parse_line() with attributes and key-value attributes' '
	cat >in <<-\EOF &&
	http://example.com/bundle1.bdl x a=b y c=d z e=f a=b
	EOF


	cat >expect <<-\EOF &&
	http://example.com/bundle1.bdl [attr: x] [kv: a => b] [attr: y] [kv: c => d] [attr: z] [kv: e => f] [kv: a => b]
	EOF

	test-tool bundle-uri parse <in >actual 2>err &&
	test_must_be_empty err &&
	test_cmp expect actual
'

test_expect_success 'bundle_uri_parse_line() parsing edge cases: extra SP' '
	cat >in <<-\EOF &&
	http://example.com/bundle1.bdl one-space
	http://example.com/bundle1.bdl  two-space
	http://example.com/bundle1.bdl   three-space
	EOF

	# We are anal just the one SP
	cat >expect <<-\EOF &&
	http://example.com/bundle1.bdl [attr: one-space]
	http://example.com/bundle1.bdl [attr: ] [attr: two-space]
	http://example.com/bundle1.bdl [attr: ] [attr: ] [attr: three-space]
	EOF

	test-tool bundle-uri parse <in >actual 2>err &&
	test_must_be_empty err &&
	test_cmp expect actual
'

test_expect_success 'bundle_uri_parse_line() parsing edge cases: multiple = in key-values' '
	cat >in <<-\EOF &&
	http://example.com/bundle1.bdl k=v=extra
	http://example.com/bundle2.bdl a=b k=v=extra c=d
	EOF

	cat >err.expect <<-\EOF &&
	error: expected `k` or `k=v` in column 1 of bundle-uri line '"'"'http://example.com/bundle1.bdl k=v=extra'"'"', got '"'"'k=v=extra'"'"'
	error: bad line: http://example.com/bundle1.bdl k=v=extra
	error: expected `k` or `k=v` in column 2 of bundle-uri line '"'"'http://example.com/bundle2.bdl a=b k=v=extra c=d'"'"', got '"'"'k=v=extra'"'"'
	error: bad line: http://example.com/bundle2.bdl a=b k=v=extra c=d
	EOF

	# We fail, but try to continue parsing regardless
	cat >expect <<-\EOF &&
	http://example.com/bundle1.bdl
	http://example.com/bundle2.bdl [kv: a => b] [kv: c => d]
	EOF

	test_must_fail test-tool bundle-uri parse <in >actual 2>err.actual &&
	test_cmp err.expect err.actual &&
	test_cmp expect actual
'

test_done
