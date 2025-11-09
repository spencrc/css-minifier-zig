const std = @import("std");

// Lexical analysis
// Each blob of characters in a sequence is a lexeme (raw subtrings of source code)
// Making lexemes also allows us to find tokens (keywords which shape language's grammar)

pub const TokenType = enum {
    IDENT,
    COMMENT,
    FUNCTION,
    AT_KEYWORD,
    HASH,
    STRING,
    BAD_STRING,
    URL,
    BAD_URL,
    DELIMITER,
    NUMBER,
    PERCENTAGE,
    DIMENSION,
    WHITESPACE,
    CDO,
    CDC,
    LEFT_SQUARE,
    RIGHT_SQUARE,
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_CURLY,
    RIGHT_CURLY,
    COMMA,
    COLON,
    SEMICOLON,
    EOF,
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,

    pub fn init(t: TokenType, lexeme: []const u8) Token {
        return Token{
            .type = t,
            .lexeme = lexeme,
        };
    }
};

pub const Scanner = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: std.ArrayList(Token) = .empty,
    start: usize = 0,
    current: usize = 0,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Scanner {
        return Scanner{
            .allocator = allocator,
            .source = source,
        };
    }

    pub fn deinit(self: *Scanner) void {
        self.tokens.deinit(self.allocator);
    }

    pub fn scan_tokens(self: *Scanner) !*std.ArrayList(Token) {
        while (!self.is_at_end()) {
            self.start = self.current;
            try self.scan_token();
        }

        try self.add_token(.EOF);
        return &self.tokens;
    }

    fn scan_token(self: *Scanner) !void {
        const c = self.advance();
        switch (c) {
            '/' => {
                const current = self.peek() orelse {
                    try self.add_token(.DELIMITER);
                    return;
                };
                if (current == '*') {
                    _ = self.advance();
                    self.consume_comment();
                } else try self.add_token(.DELIMITER);
            },
            ' ', '\t', '\n', '\r', '\x0C' => {},
            '"' => try self.consume_string_token(),
            '(' => try self.add_token(.LEFT_PAREN),
            ')' => try self.add_token(.RIGHT_PAREN),
            '{' => try self.add_token(.LEFT_CURLY),
            '}' => try self.add_token(.RIGHT_CURLY),
            ',' => try self.add_token(.COMMA),
            ';' => try self.add_token(.SEMICOLON),
            '[' => try self.add_token(.LEFT_SQUARE),
            ']' => try self.add_token(.RIGHT_SQUARE),
            ':' => try self.add_token(.COLON),
            '@' => {
                //if is the start of an identifier, scan at_keyword
                //else, add delimiter
            },
            '#' => {
                //if is a hash, scan hash
                //else, add delimiter
            },
            '>', '+', '!', '=', '%', '~', '|', '^', '$', '*', '.' => try self.add_token(.DELIMITER),
            //TODO: add < for <!-- --> scanning
            else => {
                if (isIdentStartCodePoint(c)) {
                    try self.consume_identlike_token();
                } else if (std.ascii.isDigit(c)) {
                    try self.consume_numeric_token();
                } else {
                    std.log.err("Unexpected char: <{c}>", .{c});
                    return error.UnexpectedCharacter;
                }
            },
        }
    }

    fn consume_comment(self: *Scanner) void {
        while (!self.is_at_end()) {
            const current = self.peek() orelse break;
            const next = self.peek_ahead(1) orelse break;
            if (current == '*' and next == '/') {
                _ = self.advance();
                _ = self.advance();
                break;
            }
            _ = self.advance();
        }
    }

    fn consume_numeric_token(self: *Scanner) !void {
        try self.consume_number();

        if (self.peek()) |current| {
            if (current == '%') {
                _ = self.advance();
                return try self.add_token(.PERCENTAGE);
            } else dimension: {
                // technically not a perfect implementation, see:
                // https://www.w3.org/TR/css-syntax-3/#would-start-an-identifier
                if (!isIdentStartCodePoint(current))
                    break :dimension;
                const next_1 = self.peek_ahead(1) orelse break :dimension;
                const next_2 = self.peek_ahead(2) orelse break :dimension;
                if (isIdentStartCodePoint(next_1) and
                    isIdentStartCodePoint(next_2))
                {
                    try self.consume_ident_sequence();
                    return try self.add_token(.DIMENSION);
                }
            }
        }

        try self.add_token(.NUMBER);
    }

    fn consume_identlike_token(self: *Scanner) !void {
        try self.consume_ident_sequence();
        const string = std.ascii.toLower(self.source[self.start..self.current]); //result of self.consume_ident_sequence()

        url_or_function: {
            var current = self.peek() orelse break :url_or_function;
            var next_1: u8 = undefined;
            if (std.mem.eql(
                u8,
                string,
                "url",
            )) {
                if (current == '(') {
                    _ = self.advance();

                    while (true) {
                        current = self.peek() orelse break :url_or_function;
                        next_1 = self.peek_ahead(1) orelse break :url_or_function;
                        if (std.ascii.isWhitespace(current) and
                            std.ascii.isWhitespace(next_1))
                        {
                            _ = self.advance();
                        } else break;
                    }
                    current = self.peek() orelse break :url_or_function;
                    next_1 = self.peek_ahead(1) orelse break :url_or_function;
                    if (current == '\'' or
                        current == '"' or
                        (std.ascii.isWhitespace(current) and (next_1 == '\'' or next_1 == '"')))
                    {
                        return try self.add_token(.FUNCTION);
                    } else {
                        //consume url token
                    }
                }
            } else if (current == '(') {
                _ = self.advance();
                return try self.add_token(.FUNCTION);
            }
        }

        try self.add_token(.IDENT);
    }

    fn consume_string_token(self: *Scanner) !void {
        //this skips the first quotation mark, as it was consumed in scan_token (meaning it's located at self.start)
        while (!self.is_at_end()) {
            const c = self.advance();
            switch (c) {
                '"' => {
                    try self.add_token(.STRING);
                    return;
                }, //closing quotation marks
                '\n' => {
                    try self.add_token(.BAD_STRING);
                    return;
                },
                //need to handle escape sequences other than \n here!
                else => continue,
            }
        }
        //No closing quote at EOF, bad string
        try self.add_token(.BAD_STRING);
    }

    fn consume_ident_sequence(self: *Scanner) !void {
        while (!self.is_at_end()) {
            const c = self.peek() orelse break;
            if (isIdentStartCodePoint(c) or std.ascii.isDigit(c) or c == '-') {
                _ = self.advance();
            } else {
                break;
            }
            //need to handle escape sequences here!
        }
    }

    fn consume_number(self: *Scanner) !void {
        var current = self.peek() orelse return;
        var next_1: u8 = undefined;
        var next_2: u8 = undefined;

        if (current == '+' or current == '-') {
            _ = self.advance();
            current = self.peek() orelse return;
        }

        while (!self.is_at_end() and std.ascii.isDigit(current)) {
            _ = self.advance();
            current = self.peek() orelse return;
        }

        next_1 = self.peek_ahead(1) orelse return;
        if (current == '.' and std.ascii.isDigit(next_1)) {
            _ = self.advance();
            _ = self.advance();
            current = self.peek() orelse return;
            while (!self.is_at_end() and std.ascii.isDigit(current)) {
                _ = self.advance();
                current = self.peek() orelse return;
            }
        }

        next_1 = self.peek_ahead(1) orelse return;
        if (current == 'E' or current == 'e') {
            if (next_1 == '-' or next_1 == '+') {
                next_2 = self.peek_ahead(2) orelse return;
                if (std.ascii.isDigit(next_2)) {
                    _ = self.advance();
                    _ = self.advance();
                    _ = self.advance();
                    current = self.peek() orelse return;
                    while (!self.is_at_end() and std.ascii.isDigit(current)) {
                        _ = self.advance();
                        current = self.peek() orelse return;
                    }
                }
            } else if (std.ascii.isDigit(next_1)) {
                _ = self.advance();
                _ = self.advance();
                current = self.peek() orelse return;
                while (!self.is_at_end() and std.ascii.isDigit(current)) {
                    _ = self.advance();
                    current = self.peek() orelse return;
                }
            }
        }
    }

    fn add_token(self: *Scanner, t: TokenType) !void {
        const new_token = Token.init(t, self.source[self.start..self.current]);
        try self.tokens.append(self.allocator, new_token);
    }

    fn is_at_end(self: *Scanner) bool {
        return self.current >= self.source.len;
    }

    fn advance(self: *Scanner) u8 {
        const c: u8 = self.source[self.current];
        self.current += 1;
        return c;
    }

    fn peek(self: *Scanner) ?u8 {
        if (self.is_at_end())
            return null;
        return self.source[self.current];
    }

    fn peek_ahead(self: *Scanner, offset: usize) ?u8 {
        if (self.current + offset >= self.source.len)
            return null;
        return self.source[self.current + offset];
    }

    fn isIdentStartCodePoint(c: u8) bool {
        return std.ascii.isAlphabetic(c) or c >= 0x80 or c == '_';
    }
};
