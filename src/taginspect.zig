// taginspect.zig - tag classification and validation
//
// Classify tags by role, validate cross-references between tags,
// detect anomalies and required-but-missing tag sets.

const types = @import("types.zig");

pub const TagRole = enum(u8) {
    required = 1,
    optional = 2,
    private = 3,
    unknown = 0,
};

pub const TagInfo = struct {
    signature: u32 = 0,
    role: TagRole = .unknown,
    is_shared: bool = false,
    share_count: u32 = 1,
    valid: bool = true,
    references_ok: bool = true,
    body_size: u32 = 0,
    pool_idx: i32 = -1,
};

pub const InspectionResult = struct {
    tag_infos: [types.MAX_TAGS]TagInfo = undefined,
    count: usize = 0,
    required_present: u32 = 0,
    required_missing: u32 = 0,
    optional_present: u32 = 0,
    private_present: u32 = 0,
    anomalies: u32 = 0,
    overlap_pairs: u32 = 0,
    zero_size_tags: u32 = 0,
    oob_tags: u32 = 0,
};

fn tagRole(sig: u32) TagRole {
    // Required tags per spec
    const required = [_]u32{
        types.sig('d', 'e', 's', 'c'),
        types.sig('w', 't', 'p', 't'),
        types.sig('c', 'p', 'r', 't'),
    };
    for (required) |r| {
        if (sig == r) return .required;
    }
    // Well-known optional tags
    const optional = [_]u32{
        types.sig('r', 'T', 'R', 'C'),
        types.sig('g', 'T', 'R', 'C'),
        types.sig('b', 'T', 'R', 'C'),
        types.sig('r', 'X', 'Y', 'Z'),
        types.sig('g', 'X', 'Y', 'Z'),
        types.sig('b', 'X', 'Y', 'Z'),
        types.sig('A', '2', 'B', '0'),
        types.sig('B', '2', 'A', '0'),
        types.sig('D', '2', 'B', '0'),
        types.sig('c', 'h', 'a', 'd'),
        types.sig('c', 'l', 'r', 't'),
        types.sig('n', 'c', 'l', '2'),
    };
    for (optional) |o| {
        if (sig == o) return .optional;
    }
    // Unknown or private (vendor) tags
    if (sig & 0x80000000 != 0) return .private;
    return .unknown;
}

pub fn inspect(p: *const types.Profile) InspectionResult {
    var result = InspectionResult{};
    if (p.tags == null) return result;

    result.count = p.tag_count;

    var i: usize = 0;
    while (i < p.tag_count and i < types.MAX_TAGS) : (i += 1) {
        const t = p.tags.?[i];
        var info = TagInfo{};
        info.signature = t.signature;
        info.role = tagRole(t.signature);
        info.body_size = t.size;
        info.pool_idx = t.pool_idx;

        // Check for zero-size tags
        if (t.size == 0) {
            info.valid = false;
            result.zero_size_tags += 1;
        }

        // Check OOB
        if (@as(usize, t.offset) + @as(usize, t.size) > p.buf_size) {
            info.valid = false;
            result.oob_tags += 1;
        }

        // Check sharing
        var j: usize = 0;
        while (j < p.tag_count) : (j += 1) {
            if (j != i and p.tags.?[j].offset == t.offset and t.offset > 0) {
                info.is_shared = true;
                info.share_count += 1;
            }
        }

        // Check for overlapping (non-shared) tag bodies
        j = 0;
        while (j < p.tag_count) : (j += 1) {
            if (j == i) continue;
            const tj = p.tags.?[j];
            if (tj.offset == t.offset) continue;
            const a_start = t.offset;
            const a_end = t.offset + t.size;
            const b_start = tj.offset;
            const b_end = tj.offset + tj.size;
            if (a_start < b_end and b_start < a_end) {
                result.overlap_pairs += 1;
            }
        }

        switch (info.role) {
            .required => result.required_present += 1,
            .optional => result.optional_present += 1,
            .private => result.private_present += 1,
            .unknown => {},
        }

        result.tag_infos[i] = info;
    }

    // Check for required-but-missing
    const required_sigs = [_]u32{
        types.sig('d', 'e', 's', 'c'),
        types.sig('w', 't', 'p', 't'),
        types.sig('c', 'p', 'r', 't'),
    };
    for (required_sigs) |rs| {
        var found = false;
        i = 0;
        while (i < p.tag_count) : (i += 1) {
            if (p.tags.?[i].signature == rs) {
                found = true;
                break;
            }
        }
        if (!found) result.required_missing += 1;
    }

    // Count anomalies
    result.anomalies = result.zero_size_tags + result.oob_tags + result.required_missing;
    result.overlap_pairs /= 2; // Each pair counted twice

    return result;
}

// Suggest minimum tag set for a valid profile
pub fn minimalTagSet(space: types.Colorspace) [10]u32 {
    var tags = [_]u32{0} ** 10;
    var idx: usize = 0;

    // Always required
    tags[idx] = types.sig('d', 'e', 's', 'c');
    idx += 1;
    tags[idx] = types.sig('w', 't', 'p', 't');
    idx += 1;
    tags[idx] = types.sig('c', 'p', 'r', 't');
    idx += 1;

    switch (space) {
        .rgb => {
            tags[idx] = types.sig('r', 'T', 'R', 'C');
            idx += 1;
            tags[idx] = types.sig('g', 'T', 'R', 'C');
            idx += 1;
            tags[idx] = types.sig('b', 'T', 'R', 'C');
            idx += 1;
            tags[idx] = types.sig('r', 'X', 'Y', 'Z');
            idx += 1;
            tags[idx] = types.sig('g', 'X', 'Y', 'Z');
            idx += 1;
            tags[idx] = types.sig('b', 'X', 'Y', 'Z');
            idx += 1;
        },
        .gray => {
            tags[idx] = types.sig('k', 'T', 'R', 'C');
            idx += 1;
        },
        else => {
            tags[idx] = types.sig('A', '2', 'B', '0');
            idx += 1;
        },
    }
    return tags;
}

// Compute a tag "diversity score" (how many distinct element kinds)
pub fn diversityScore(p: *const types.Profile) f32 {
    var kinds: [8]bool = [_]bool{false} ** 8;
    if (p.pool.items) |items| {
        var i: usize = 0;
        while (i < p.pool.count) : (i += 1) {
            if (items[i]) |el| {
                kinds[@intFromEnum(el.kind)] = true;
            }
        }
    }
    var count: u32 = 0;
    for (kinds) |k| {
        if (k) count += 1;
    }
    return @as(f32, @floatFromInt(count)) / 7.0;
}
