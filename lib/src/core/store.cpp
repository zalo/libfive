#include "ao/core/store.hpp"
#include "ao/core/token.hpp"

Store::~Store()
{
    for (auto c : constants)
    {
        delete c.second;
    }

    for (auto row : ops)
    {
        for (auto sub : row)
        {
            for (auto t : sub)
            {
                delete t.second;
            }
        }
    }
}

Token* Store::constant(double v)
{
    if (constants.find(v) == constants.end())
    {
        constants[v] = new Token(v);
    }
    return constants[v];
}

Token* Store::operation(Opcode op, Token* a, Token* b, Token* cond)
{
    // Special cases to handle identity operations
    if (op == OP_ADD)
    {
        if (a->op == OP_CONST && a->value == 0)
        {
            return b;
        }
        if (b->op == OP_CONST && b->value == 0)
        {
            return a;
        }
    }
    else if (op == OP_SUB)
    {
        if (a->op == OP_CONST && a->value == 0)
        {
            return operation(OP_NEG, b);
        }
        if (b->op == OP_CONST && b->value == 0)
        {
            return a;
        }
    }
    else if (op == OP_MUL)
    {
        if (a->op == OP_CONST)
        {
            if (a->value == 0)
            {
                return a;
            }
            else if (a->value == 1)
            {
                return b;
            }
        }
        if (b->op == OP_CONST)
        {
            if (b->value == 0)
            {
                return b;
            }
            else if (b->value == 1)
            {
                return a;
            }
        }
    }

    // Otherwise, construct a new Token and add it to the ops set
    const auto t = new Token(op, a, b, cond);

    if (ops.size() <= t->weight)
    {
        ops.resize(t->weight + 1);
    }

    auto& row = ops[t->weight][t->op];
    if (row.find({a,b,cond}) == row.end())
    {
        row[{a,b,cond}] = t;
    }
    else
    {
        delete t;
    }

    return row[{a,b,cond}];
}

void Store::clearFound()
{
    for (auto a : ops)
    {
        for (auto b : a)
        {
            for (auto c : b)
            {
                c.second->found = false;
            }
        }
    }
}

void Store::markFound(Token* root)
{
    clearFound();

    root->found = true;

    for (auto itr = ops.rbegin(); itr != ops.rend(); ++itr)
    {
        for (auto b : *itr)
        {
            for (auto c : b)
            {
                Token* const t = c.second;
                if (t->found)
                {
                    if (t->a)
                    {
                        t->a->found = true;
                    }
                    if (t->b)
                    {
                        t->b->found = true;
                    }
                }
            }
        }
    }
}
