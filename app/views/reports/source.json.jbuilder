json.array! @statements do | statement |
    json.partial! 'statements/statement', statement: statement
end