%% PeTTa WASM Bundle - Auto-generated for browser execution
%% This file is a concatenation of all PeTTa Prolog source files
%% with WASM compatibility patches applied.

:- assertz(silent(true)).
:- assertz(working_dir("/")).

%% ======== parser.pl ========
:- use_module(library(dcg/basics)). %blanks/0, number/1, string_without/2

%Generate a MeTTa S-expression string from the Prolog list (inverse parsing):
swrite(Term, String) :- phrase(swrite_exp(Term), Codes),
                        string_codes(String, Codes).
swrite_exp(Var)   --> { var(Var) }, !, "$", { term_to_atom(Var, A), atom_codes(A, Cs) }, Cs.
swrite_exp(Num)   --> { number(Num) }, !, { number_codes(Num, Cs) }, Cs.
swrite_exp(Str)   --> { string(Str) }, !, "\"", { string_codes(Str, Cs), escape_quotes(Cs, Es) }, Es, "\"".
swrite_exp(Atom)  --> { atom(Atom) }, !, atom(Atom).
swrite_exp([H|T]) --> { \+ is_list([H|T]) }, !, "(", atom(cons), " ", swrite_exp(H), " ", swrite_exp(T), ")".
swrite_exp([H|T]) --> !, "(", seq([H|T]), ")".
swrite_exp([])    --> !, "()".
swrite_exp(Term)  --> { Term =.. [F|Args] }, "(", atom(F), ( { Args == [] } -> [] ; " ", seq(Args) ), ")".
seq([X])    --> swrite_exp(X).
seq([X|Xs]) --> swrite_exp(X), " ", seq(Xs).
escape_quotes([], []).
escape_quotes([0'"|T], [0'\\,0'"|R]) :- !, escape_quotes(T, R).
escape_quotes([H|T], [H|R]) :- escape_quotes(T, R).

%Read S string or atom, extract codes, and apply DCG (parsing):
sread(S, T) :- ( atom_string(A, S),
                 atom_codes(A, Cs),
                 phrase(sexpr(T, [], _), Cs)
               -> true ; format(atom(Msg), 'Parse error in form: ~w', [S]), throw(error(syntax_error(Msg), none)) ).

%An S-Expression is a parentheses-nesting of S-Expressions that are either numbers, variables, sttrings, or atoms:
sexpr(S,E,E)  --> blanks, string_lit(S), blanks, !.
sexpr(T,E0,E) --> blanks, "(", blanks, seq(T,E0,E), blanks, ")", blanks, !.
sexpr(N,E,E)  --> blanks, number(N), ( lookahead_any(" ()\t\n\r") ; \+ [_] ), blanks, !.
sexpr(V,E0,E) --> blanks, var_symbol(V,E0,E), blanks, !.
sexpr(A,E,E)  --> blanks, atom_symbol(A), blanks.

%Helper for strange atoms that aren't numbers, e.g. 1_2_3:
lookahead_any(Terms, S, E) :- string_codes(Terms,SC), S = [Head | _], member(Head,SC), !, S = E.

%Recursive processing of S-Expressions within S-Expressions:
seq([X|Xs],E0,E2) --> sexpr(X,E0,E1), blanks, seq(Xs,E1,E2).
seq([],E,E)       --> [].

%Variables start with $, and keep track of them: re-using exising Prolog variables for variables of same name:
var_symbol(V,E0,E) --> "$", token(Cs), { atom_chars(N, Cs), ( N == '_' -> V = _, E = E0 ; memberchk(N-V0, E0) -> V = V0, E = E0 ; V = _, E = [N-V|E0] ) }.

%Atoms are derived from tokens:
atom_symbol(A) --> token(Cs), { string_codes("\"", [Q]), ( Cs = [Q|_] -> append([Q|Body], [Q], Cs), %"str" as string
                                                                         string_codes(A, Body)
                                                                       ; atom_codes(R, Cs),         %others are atoms
                                                                         ( R = 'True' -> A = true
                                                                                       ; R = 'False'
                                                                                         -> A = false
                                                                                          ; A = R ))}.

%A token is a non-empty string without whitespace:
token(Cs) --> string_without(" \t\r\n()", Cs), { Cs \= [] }.

%Just string literal handling from here-on:
string_lit(S) --> "\"", string_chars(Cs), "\"", { string_codes(S, Cs) }.
string_chars([]) --> [].
string_chars([C|Cs]) --> [C], { C =\= 0'", C =\= 0'\\ }, !, string_chars(Cs).
string_chars([C|Cs]) --> "\\", [X], { (X=0'n->C=10; X=0't->C=9; X=0'r->C=13; C=X) }, string_chars(Cs).


%% ======== specializer.pl ========
:- dynamic ho_specialization/2.

%Maybe specializes HV(AVs) if not already ongoing, and if specialization fails, nothing changes and specneeded is restored:
maybe_specialize_call(HV, AVs, Out, Goal) :- setup_call_cleanup( (catch(nb_getval(specneeded,Prev),_,Prev = []), nb_setval(specneeded,false)),
                                                                 specialize_call(HV, AVs, Out, Goal),
                                                                 (Prev == true -> nb_setval(specneeded,Prev)) ).

% Helper predicate to replace all variables with 'VAR'
replace_vars_with_var(Var, 'VAR') :- var(Var), !.
replace_vars_with_var(Term, NewTerm) :- (is_list(Term) -> maplist(replace_vars_with_var, Term, NewTerm)
                                                        ;  Term = NewTerm).

%Specialize a call by creating and translating a specialized version of the MeTTa code:
specialize_call(HV, AVs, Out, Goal) :- %1. Retrieve a copy of all meta-clauses stored for HV:
                                       catch(nb_getval(HV, MetaList0), _, fail),
                                       copy_term(MetaList0, MetaList),
                                       %2. Copy all clause variables eligible for specialization across all meta-clauses:
                                       bagof(HoVar, ArgsNorm^BodyExpr^HoBinds^HoBindsPerArg^
                                                    ( member(fun_meta(ArgsNorm, BodyExpr), MetaList),
                                                      maplist(specializable_vars(BodyExpr), AVs, ArgsNorm, HoBinds),
                                                      member(HoBindsPerArg, HoBinds),
                                                      member(HoVar, HoBindsPerArg),
                                                      nonvar(HoVar) ), BindSet),
                                       %3. Build the specialization name from the concrete higher-order bind set:
                                       replace_vars_with_var(BindSet, CleanBindSet),
                                       format(atom(SpecName), "~w_Spec_~w",[HV, CleanBindSet]),
                                       %4. Specialize, but only if not already specialized:
                                       ( ho_specialization(HV, SpecName)
                                         ; ( %4.1. Otherwise register the specialization:
                                             register_fun(SpecName),
                                             assertz(ho_specialization(HV, SpecName)),
                                             length(AVs, N),
                                             Arity is N + 1,
                                             assertz(arity(SpecName, Arity)),
                                             ( %4.2. Re-use the type definition of the parent function for the specialization:
                                               findall(TypeChain, catch(match('&self', [':', HV, TypeChain], TypeChain, TypeChain), _, fail), TypeChains),
                                               forall(member(TypeChain, TypeChains), add_sexp('&self', [':', SpecName, TypeChain])),
                                               %4.3 Translate specialized MeTTa clauseses to Prolog, keeping track of the function we are compiling through recursion:
                                               maplist({SpecName}/[fun_meta(ArgsNorm,BodyExpr),clause_info(Input,Clause)]>>
                                                       ( Input = [=,[SpecName|ArgsNorm],BodyExpr], translate_clause(Input,Clause,false) ), MetaList, ClauseInfos),
                                               %4.4 Only proceeed specializing if this or any recursive call profited from specialization with the specialized function at head position:
                                               nb_getval(specneeded, true),
                                               %4.5 Assert and print each of the created specializations:
                                               forall(member(clause_info(Input, Clause), ClauseInfos),
                                               ( asserta(Clause, Ref),
                                                 assertz(translated_from(Ref, Input)),
                                                 add_sexp('&self', Input),
                                                 format(atom(Label), "metta specialization (~w)", [SpecName]),
                                                 maybe_print_compiled_clause(Label, Input, Clause) ))
                                               %4.6 Ok specialized, but if we did not succeed ensure the specialization is retracted:
                                               -> true ; format("Not specialized ~w~n", [SpecName/Arity]),
                                                         retractall(fun(SpecName)),
                                                         abolish(SpecName, Arity),
                                                         retractall(arity(SpecName,Arity)),
                                                         retractall(ho_specialization(HV, SpecName)), fail ))), !,
                                       %5. Generate call to the specialized function:
                                       append(AVs, [Out], CallArgs),
                                       Goal =.. [SpecName|CallArgs].

%Extracts clause-head variables and their call-site copies, producing eligible Var–Copy pairs for specialization:
specializable_vars(BodyExpr, Value, Arg, HoVars) :- term_variables(Arg, Vars),
                                                    copy_term(Arg-Vars, ArgCopy-VarsCopy),
                                                    traverse_list([A,V]>>(nonvar(V) ->  V = A;  true), ArgCopy, Value),
                                                    eligible_var_pairs(Vars, VarsCopy, BodyExpr, HoVars).

traverse_list(Pred, From, Into) :- (is_list(From),is_list(Into) -> maplist(traverse_list(Pred),From,Into)
                                                                 ; call(Pred, From, Into)).

%Selects and unifies variable–argument pairs that act as higher-order or head operands in the body:
eligible_var_pairs([], [], _, []).
eligible_var_pairs([Var|Vars], [Copy|Copies], BodyExpr, HoVars) :- ( specializable_arg(Copy), (var_use_check(head, Var, BodyExpr) ; var_use_check(ho, Var, BodyExpr))
                                                                     -> Var = Copy,
                                                                        HoVars = [Var|RestHoVars]
                                                                      ; HoVars = RestHoVars ),
                                                                   eligible_var_pairs(Vars, Copies, BodyExpr, RestHoVars).

%If Var appears at list head it means function call, meaning specialization is needed, and detect when used as HOL arg
var_use_check(head, Var, [Head|_]) :- Var == Head,
                                      nb_setval(specneeded, true).
var_use_check(ho, Var, [Head|Args]) :- specializable_arg(Head),
                                       member(Arg, Args),
                                       ( Var == Arg
                                       ; is_list(Arg),
                                         var_use_check(ho, Var, Arg) ).
var_use_check(Mode, Var, L) :- is_list(L),
                               member(E, L),
                               is_list(E),
                               var_use_check(Mode, Var, E).

%Tests whether an argument represents a specializable function or partial application:
specializable_arg(Arg) :- nonvar(Arg), 
                          ( fun(Arg) ; Arg = partial(_, _) ).

%Forget function symbol:
forget_symbol(Name) :- retractall('&self'(=, [Name|_], _)),
                       retractall('&self'(:, Name, _)),
                       findall(Ref, ( current_predicate(Name/A), functor(H, Name, A), clause(H, _, Ref) ), Refs),
                       forall(member(R, Refs), erase(R)),
                       retractall(arity(Name,_)),
                       retractall(fun(Name)),
                       catch(nb_delete(Name), _, true),
                       retractall(ho_specialization(Name,_)).

%Invalidate all specializations:
invalidate_specializations(F) :-
    findall(Spec, ho_specialization(F, Spec), Specs),
    forall(member(S, Specs), invalidate_specializations(S)),
    forall(member(S, Specs), forget_symbol(S)),
    retractall(ho_specialization(F,_)).


%% ======== spaces.pl ========
%Since both normal add-attom call and function additions needs to add the S-expression:
add_sexp(Space, [Rel|Args]) :- Term =.. [Space, Rel | Args],
                               assertz(Term).

%Same but for removal:
remove_sexp(Space, [Rel|Args]) :- Term =.. [Space, Rel | Args],
                                  retractall(Term).

%Add a function atom:
'add-atom'(Space, Term, true) :- Term = [=,[FAtom|W],_], !,
                                 add_sexp(Space, Term),
                                 register_fun(FAtom),
                                 length(W, N),
                                 Arity is N + 1,
                                 assertz(arity(FAtom,Arity)),
                                 once(translate_clause(Term, Clause)),
                                 assertz(Clause, Ref),
                                 assertz(translated_from(Ref, Term)),
                                 invalidate_specializations(FAtom),
                                 maybe_print_compiled_clause("added function", Term, Clause).

%Add an atom to the space:
'add-atom'(Space, Term, true) :- add_sexp(Space, Term).

%%Remove a function atom:
'remove-atom'('&self', Term, Removed) :- Term = [=,[F|Args],Body], !,
                                         remove_sexp('&self', Term),
                                         catch(nb_getval(F, Prev), _, Prev = []),
                                         (   select(fun_meta(Args, Body), Prev, Rest)
                                             -> ( Rest == [] -> nb_delete(F)
                                                              ; nb_setval(F, Rest) ) ; true ),
                                         findall(Ref, translated_from(Ref, Term), Refs),
                                         forall(member(Ref, Refs), erase(Ref)),
                                         retractall(translated_from(_, Term)),
                                         invalidate_specializations(F),
                                         ( \+ ( current_predicate(F/A), functor(H2, F, A), clause(H2, _, _) )
                                           -> retractall(fun(F)) ; true ),
                                         ( Refs = [] -> Removed = false ; Removed = true ).

%Remove all same atoms:
'remove-atom'(Space, Term, true) :- remove_sexp(Space, Term).

%Match for conjunctive pattern
match(_, LComma, OutPattern, Result) :- LComma == [','], !,
                                        Result = OutPattern.
match(Space, [Comma|[Head|Tail]], OutPattern, Result) :- Comma == ',', !,
                                                         append([Space], Head, List),
                                                         Term =.. List,
                                                         catch(Term, _, fail),
                                                         \+ cyclic_term(OutPattern),
                                                         match(Space, [','|Tail], OutPattern, Result).

% When the pattern list itself is a variable -> enumerate all atoms
match(Space, PatternVar, OutPattern, Result) :- var(PatternVar), !,
                                                'get-atoms'(Space, PatternVar),
                                                \+ cyclic_term(OutPattern),
                                                Result = OutPattern.

%Match for pattern:
match(Space, [Rel|PatArgs], OutPattern, Result) :- Term =.. [Space, Rel | PatArgs],
                                                   catch(Term, _, fail),
                                                   \+ cyclic_term(OutPattern),
                                                   Result = OutPattern.

%Get all atoms in space, irregard of arity:
'get-atoms'(Space, Pattern) :- current_predicate(Space/Arity),
                               functor(Head, Space, Arity),
                               clause(Head, true),
                               Head =.. [Space | Pattern].


%% ======== translator.pl ========
%Pattern matching, structural and functional/relational constraints on arguments:
constrain_args(X, X, []) :- (var(X); atomic(X)), !.
constrain_args([F, A, B], Out, Goals) :- nonvar(F),
                                         F == cons,
                                         constrain_args(A, A1, G1),
                                         constrain_args(B, B1, G2),
                                         Out = [A1|B1],
                                         append(G1, G2, Goals), !.
constrain_args([F|Args], Var, Goals) :- atom(F),
                                        fun(F), !,
                                        translate_expr([F|Args], GoalsExpr, Var),
                                        flatten(GoalsExpr, Goals).
constrain_args(In, Out, Goals) :- maplist(constrain_args, In, Out, NestedGoalsList),
                                  flatten(NestedGoalsList, Goals), !.

%Flatten (= Head Body) MeTTa function into Prolog Clause:
translate_clause(Input, (Head :- BodyConj)) :- translate_clause(Input, (Head :- BodyConj), true).
translate_clause(Input, (Head :- BodyConj), ConstrainArgs) :-
                                               Input = [=, [F|Args0], BodyExpr],
                                               ( ConstrainArgs -> maplist(constrain_args, Args0, Args1, GoalsA),
                                                                  flatten(GoalsA,GoalsPrefix)
                                                                ; Args1 = Args0, GoalsPrefix = [] ),
                                               catch(nb_getval(F, Prev), _, Prev = []),
                                               nb_setval(F, [fun_meta(Args1, BodyExpr) | Prev]),
                                               translate_expr(BodyExpr, GoalsBody, ExpOut),
                                               (  nonvar(ExpOut) , ExpOut = partial(Base,Bound)
                                               -> current_predicate(Base/Arity), length(Bound, N), M is (Arity - N) - 1,
                                                  length(ExtraArgs, M), append([Bound,ExtraArgs,[Out]],CallArgs), Goal =.. [Base|CallArgs],
                                                  append(GoalsBody,[Goal],FinalGoals), append(Args1,ExtraArgs,HeadArgs)
                                               ; FinalGoals= GoalsBody , HeadArgs = Args1, Out = ExpOut ),
                                               append(HeadArgs, [Out], FinalArgs),
                                               Head =.. [F|FinalArgs],
                                               append(GoalsPrefix, FinalGoals, Goals),
                                               goals_list_to_conj(Goals, BodyConj).

%Print compiled clause:
maybe_print_compiled_clause(_, _, _) :- silent(true), !.
maybe_print_compiled_clause(Label, FormTerm, Clause) :-
    swrite(FormTerm, FormStr),
    format("\e[33m-->  ~w  -->~n\e[36m~w~n\e[33m--> prolog clause -->~n\e[32m", [Label, FormStr]),
    portray_clause(current_output, Clause),
    format("\e[33m^^^^^^^^^^^^^^^^^^^^^~n\e[0m").

%Conjunction builder, turning goals list to a flat conjunction:
goals_list_to_conj([], true)      :- !.
goals_list_to_conj([G], G)        :- !.
goals_list_to_conj([G|Gs], (G,R)) :- goals_list_to_conj(Gs, R).

% Runtime dispatcher: call F if it's a registered fun/1, else keep as list:
reduce([F|Args], Out) :- nonvar(F), atom(F), fun(F)
                         -> % --- Case 1: callable predicate ---
                            length(Args, N),
                            Arity is N + 1,
                            ( current_predicate(F/Arity) , \+ (current_op(_, _, F), Arity =< 2)
                              -> append(Args,[Out],CallArgs),
                                 Goal =.. [F|CallArgs],
                                 catch(call(Goal),_,fail)
                               ; Out = partial(F,Args) )
                          ; % --- Case 2: partial closure ---
                            compound(F), F = partial(Base, Bound) -> append(Bound, Args, NewArgs),
                                                                     reduce([Base|NewArgs], Out)
                          ; % --- Case 3: leave unevaluated ---
                            Out = [F|Args],
                            \+ cyclic_term(Out).

%Calling reduce from aggregate function foldall needs this argument wrapping
agg_reduce(AF, Acc, Val, NewAcc) :- reduce([AF, Acc, Val], NewAcc).

%Combined expr translation to goals list
translate_expr_to_conj(Input, Conj, Out) :- translate_expr(Input, Goals, Out),
                                            goals_list_to_conj(Goals, Conj).

%Special stream operation rewrite rules before main translation
rewrite_streamops(['trace!', Arg1, Arg2],
                  [progn, ['println!', Arg1], Arg2]).
rewrite_streamops([unique, [superpose|Args]],
                  [call, [superpose, ['unique-atom', [collapse, [superpose|Args]]]]]).
rewrite_streamops([union, [superpose|A], [superpose|B]],
                  [call, [superpose, ['union-atom', [collapse, [superpose|A]],
                                                    [collapse, [superpose|B]]]]]).
rewrite_streamops([intersection, [superpose|A], [superpose|B]],
                  [call, [superpose, ['intersection-atom', [collapse, [superpose|A]],
                                                           [collapse, [superpose|B]]]]]).
rewrite_streamops([subtraction, [superpose|A], [superpose|B]],
                  [call, [superpose, ['subtraction-atom', [collapse, [superpose|A]],
                                                          [collapse, [superpose|B]]]]]).
rewrite_streamops(X, X).

%Guarded stream ops rewrite rule application, successfully avoiding copy_term:
safe_rewrite_streamops(In, Out) :- ( compound(In), In = [Op|_], atom(Op) -> rewrite_streamops(In, Out)
                                                                          ; Out = In).

%Turn MeTTa code S-expression into goals list:
translate_expr(X, [], X)          :- ((var(X) ; atomic(X)) ; X = partial(_,_)), !.
translate_expr([H0|T0], Goals, Out) :-
        safe_rewrite_streamops([H0|T0],[H|T]),
        translate_expr(H, GsH, HV),
        %--- Translator rules ---:
        ( nonvar(HV), translator_rule(HV) -> ( catch(match('&self', [':', HV, TypeChain], TypeChain, TypeChain), _, fail)
                                               -> TypeChain = [->|Xs],
                                                  append(ArgTypes, [_], Xs),
                                                  translate_args_by_type(T, ArgTypes, GsT, T1)
                                                ; translate_args(T, GsT, T1) ),
                                             append(T1,[Gs],Args),
                                             HookCall =.. [HV|Args],
                                             call(HookCall),
                                             translate_expr(Gs, GsE, Out),
                                             append([GsH,GsT,GsE],Goals)
        %--- Non-determinism ---:
        ; HV == superpose, T = [Args], is_list(Args) -> build_superpose_branches(Args, Out, Branches),
                                                        disj_list(Branches, Disj),
                                                        append(GsH, [Disj], Goals)
        ; HV == collapse, T = [E] -> translate_expr_to_conj(E, Conj, EV),
                                     append(GsH, [findall(EV, Conj, Out)], Goals)
        ; HV == cut, T = [] -> append(GsH, [(!)], Goals),
                               Out = true
        ; HV == test, T = [Expr, Expected] -> translate_expr_to_conj(Expr, Conj, Val),
                                              translate_expr(Expected, GsE, ExpVal),
                                              Goal1 = ( findall(Val, Conj, Results),
                                                        (Results = [Actual] -> true
                                                                             ; Actual = Results ) ),
                                              append(GsH, [Goal1], G1),
                                              append(G1, GsE, G2),
                                              append(G2, [test(Actual, ExpVal, Out)], Goals)
        ; HV == once, T = [X] -> translate_expr_to_conj(X, Conj, Out),
                                 append(GsH, [once(Conj)], Goals)
        ; HV == hyperpose, T = [L] -> build_hyperpose_branches(L, Branches),
                                      append(GsH, [concurrent_and(member((Goal,Res), Branches), (call(Goal), Out = Res))], Goals)
        ; HV == with_mutex, T = [M,X] -> translate_expr_to_conj(X, Conj, Out),
                                         append(GsH, [with_mutex(M,Conj)], Goals)
        ; HV == transaction, T = [X] -> translate_expr_to_conj(X, Conj, Out),
                                        append(GsH, [transaction(Conj)], Goals)
        %--- Sequential execution ---:
        ; HV == progn, T = Exprs -> translate_args(Exprs, GsList, Outs),
                                    append(GsH, GsList, Tmp),
                                    last(Outs, Out),
                                    Goals = Tmp
        ; HV == prog1, T = Exprs -> Exprs = [First|Rest],
                                    translate_expr(First, GsF, Out),
                                    translate_args(Rest, GsRest, _),
                                    append(GsH, GsF, Tmp1),
                                    append(Tmp1, GsRest, Goals)
        %--- Conditionals ---:
        ; HV == if, T = [Cond, Then] -> translate_expr_to_conj(Cond, ConC, Cv),
                                        translate_expr_to_conj(Then, ConT, Tv),
                                        build_branch(ConT, Tv, Out, BT),
                                        ( ConC == true -> append(GsH, [ ( Cv == true -> BT ) ], Goals)
                                                        ; append(GsH, [ ( ConC, ( Cv == true -> BT ) ) ], Goals) )
        ; HV == if, T = [Cond, Then, Else] -> translate_expr_to_conj(Cond, ConC, Cv),
                                              translate_expr_to_conj(Then, ConT, Tv),
                                              translate_expr_to_conj(Else, ConE, Ev),
                                              build_branch(ConT, Tv, Out, BT),
                                              build_branch(ConE, Ev, Out, BE),
                                              ( ConC == true -> append(GsH, [ (Cv == true -> BT ; BE) ], Goals)
                                                              ; append(GsH, [ (ConC, (Cv == true -> BT ; BE)) ], Goals) )
        ; HV == case, T = [KeyExpr, PairsExpr] -> ( select(Found0, PairsExpr, Rest0),
                                                    subsumes_term(['Empty', _], Found0),
                                                    Found0 = ['Empty', DefaultExpr],
                                                    NormalCases = Rest0
                                                    -> translate_expr_to_conj(KeyExpr, GkConj, Kv),
                                                       translate_case(NormalCases, Kv, Out, CaseGoal, KeyGoal),
                                                       translate_expr_to_conj(DefaultExpr, ConD, DOut),
                                                       build_branch(ConD, DOut, Out, DefaultThen),
                                                       Combined = ( (GkConj, CaseGoal) ;
                                                                    \+ GkConj, DefaultThen ),
                                                       append([GsH, KeyGoal, [Combined]], Goals)
                                                     ; translate_expr(KeyExpr, Gk, Kv),
                                                       translate_case(PairsExpr, Kv, Out, IfGoal, KeyGoal),
                                                       append([GsH, Gk, KeyGoal, [IfGoal]], Goals) )
        %--- Unification constructs ---:
        ; (HV == let ; HV == chain), T = [Pat, Val, In] -> translate_expr(Pat, Gp, Pv),
                                                           translate_expr(Val, Gv, V),
                                                           translate_expr(In,  Gi, Out),
                                                           append([GsH,[(Pv=V)],Gp,Gv,Gi], Goals)
        ; HV == 'let*', T = [Binds, Body] -> letstar_to_rec_let(Binds,Body,RecLet),
                                             translate_expr(RecLet,  Goals, Out)
        ; HV == sealed, T = [Vars, Expr] -> translate_expr_to_conj(Expr, Con, Val),
                                            Goals = [copy_term(Vars,[Con,Val],_,[Ncon,Out]),Ncon]
        %--- Iterating over non-deterministic generators without reification ---:
        ; HV == 'forall', T = [GF, TF]
          -> ( is_list(GF) -> GF = [GFH|GFA],
                              translate_expr(GFH, GsGFH, GFHV),
                              translate_args(GFA, GsGFA, GFAv),
                              append(GsGFH, GsGFA, GsGF),
                              GenList = [GFHV|GFAv]
                            ; translate_expr(GF, GsGF, GFHV),
                              GenList = [GFHV] ),
             translate_expr(TF, GsTF, TFHV),
             TestList = [TFHV, V],
             goals_list_to_conj(GsGF, GPre),
             GenGoal = (GPre, reduce(GenList, V)),
             append(GsH, GsTF, Tmp0),
             append(Tmp0, [( forall(GenGoal, ( reduce(TestList, Truth), Truth == true )) -> Out = true ; Out = false )], Goals)
        ; HV == 'foldall', T = [AF, GF, InitS]
          -> translate_expr_to_conj(InitS, ConjInit, Init),
             translate_expr(AF, GsAF, AFV),
             ( GF = [M|_], (M==match ; M==let ; M=='let*') -> LambdaGF = ['|->', [], GF],
                                                              translate_expr(LambdaGF, GsGF, GFHV),
                                                              GenList = [GFHV]
             ; is_list(GF) -> GF = [GFH|GFA],
                              translate_expr(GFH, GsGFH, GFHV),
                              translate_args(GFA, GsGFA, GFAv),
                              append(GsGFH, GsGFA, GsGF),
                              GenList = [GFHV|GFAv]
                            ; translate_expr(GF, GsGF, GFHV),
                              GenList = [GFHV] ),
             append(GsH, GsAF, Tmp1),
             append(Tmp1, GsGF, Tmp2),
             append(Tmp2, [ConjInit, foldall(agg_reduce(AFV, V), reduce(GenList, V), Init, Out)], Goals)
        %--- Higher-order functions with pseudo-lambdas and lambdas ---:
        ; HV == 'foldl-atom', T = [List, Init, AccVar, XVar, Body]
          -> translate_expr_to_conj(List, ConjList, L),
             translate_expr_to_conj(Init, ConjInit, InitV),
             translate_expr_to_conj(Body, BodyConj, BG),
             exclude(==(true), [ConjList, ConjInit], CleanConjs),
             append(GsH, CleanConjs, GsMid),
             append(GsMid, [foldl([XVar, AccVar, NewAcc]>>(BodyConj, ( number(BG) -> NewAcc is BG ; NewAcc = BG )), L, InitV, Out)], Goals)
        ; HV == 'map-atom', T = [List, XVar, Body]
          -> translate_expr_to_conj(List, ConjList, L),
             translate_expr_to_conj(Body, BodyCallConj, BodyCall),
             exclude(==(true), [ConjList], CleanConjs),
             append(GsH, CleanConjs, GsMid),
             append(GsMid, [maplist([XVar, Y]>>(BodyCallConj, ( number(BodyCall) -> Y is BodyCall ; Y = BodyCall )), L, Out)], Goals)
        ; HV == 'filter-atom', T = [List, XVar, Cond]
          -> translate_expr_to_conj(List, ConjList, L),
             translate_expr_to_conj(Cond, CondConj, CondGoal),
             exclude(==(true), [ConjList], CleanConjs),
             append(GsH, CleanConjs, GsMid),
             append(GsMid, [include([XVar]>>(CondConj, CondGoal), L, Out)], Goals)
        ; HV == '|->', T = [Args, Body] -> next_lambda_name(F),
                                           % find free (non-argument) variables in Body
                                           term_variables(Body, AllVars),
                                           term_variables(Args, ArgVars),
                                           exclude({ArgVars}/[V]>>memberchk_eq(V, ArgVars), AllVars, FreeVars),
                                           append(FreeVars, Args, FullArgs),
                                           % compile clause with all bound + free vars
                                           translate_clause([=, [F|FullArgs], Body], Clause),
                                           register_fun(F),
                                           assertz(Clause),
                                           format(atom(Label), "metta lambda (~w)", [F]),
                                           maybe_print_compiled_clause(Label, ['|->', Args, Body], Clause),
                                           length(FullArgs, N),
                                           Arity is N + 1,
                                           assertz(arity(F, Arity)),
                                           % emit closure capturing the environment (free vars)
                                           ( FreeVars == [] -> Out = F
                                                             ; Out = partial(F, FreeVars) )
        %--- Spaces ---:
        ; ( HV == 'add-atom' ; HV == 'remove-atom' ), T = [_,_] -> append(T, [Out], RawArgs),
                                                                   Goal =.. [HV|RawArgs],
                                                                   append(GsH, [Goal], Goals)
        ; HV == match, T = [Space, Pattern, Body] -> translate_expr(Space, G1, S),
                                                     translate_expr(Body, GsB, Out),
                                                     append(G1, [match(S, Pattern, Out, Out)], G2),
                                                     append(G2, GsB, Goals)
        %--- Predicate to compiled goal ---:
        ; HV == translatePredicate, T = [Expr] -> Expr = [S|Args],
                                                  translate_args(Args, GsArgs, ArgsOut),
                                                  Goal =.. [S|ArgsOut],
                                                  append(GsH, GsArgs, Inner),
                                                  append(Inner, [Goal], Goals)
        %--- Manual dispatch options: ---
        %Generate a predicate call on compilation, translating Args for nesting:
        ; HV == call,  T = [Expr] -> Expr = [F|Args],
                                     translate_args(Args, GsArgs, ArgsOut),
                                     append(GsH, GsArgs, Inner),
                                     append(ArgsOut, [Out], CallArgs),
                                     Goal =.. [F|CallArgs],
                                     append(Inner, [Goal], Goals)
        %Produce a dynamic dispatch, translating Args for nesting:
        ; HV == reduce, T = [Expr] -> ( var(Expr) -> translate_expr(Expr, GsH, ExprOut),
                                                     Goals = [reduce(ExprOut, Out)|GsH]
                                                   ; Expr = [F|Args],
                                                     translate_args(Args, GsArgs, ArgsOut),
                                                     append(GsH, GsArgs, Inner),
                                                     ExprOut = [F|ArgsOut],
                                                     append(Inner, [reduce(ExprOut, Out)], Goals) )
        %Invoke translator to evaluate MeTTa code as data/list:
        ; HV == eval, T = [Arg] -> append(GsH, [], Inner),
                                   Goal = eval(Arg, Out),
                                   append(Inner, [Goal], Goals)
        %Force arg to remain data/list:
        ; HV == quote, T = [Expr] -> append(GsH, [], Inner),
                                     Out = Expr,
                                     Goals = Inner
        ; HV == 'catch', T = [Expr] ->
          translate_expr(Expr, GsExpr, ExprOut),
          append(GsH, [], Inner),
          goals_list_to_conj(GsExpr, Conj),
          Goal = catch((Conj, Out = ExprOut),
                       Exception,
                       (Exception = error(Type, Ctx) -> Out = ['Error', Type, Ctx]
                                                      ; Out = ['Error', Exception])),
          append(Inner, [Goal], Goals)
        %--- Automatic 'smart' dispatch, translator deciding when to create a predicate call, data list, or dynamic dispatch: ---
        ; translate_args(T, GsT, AVs),
          append(GsH, GsT, Inner),
          %Known function => direct call:
          ( is_list(AVs), 
            ( atom(HV), fun(HV), Fun = HV, AllAVs = AVs, IsPartial = false
            ; compound(HV), HV = partial(Fun, Bound), append(Bound,AVs,AllAVs), IsPartial = true
            ) % Check for type definition [:,HV,TypeChain]
            -> findall(TypeChain, catch(match('&self', [':', Fun, TypeChain], TypeChain, TypeChain), _, fail), TypeChains),
               ( TypeChains \= []
                 -> maplist({Fun,T,GsH,IsPartial,Bound,Out}/[TypeChain,BranchGoal]>>(
                            typed_functioncall_branch(Fun, TypeChain, T, GsH, IsPartial, Bound, Out, BranchGoal)), TypeChains, Branches),
                    disj_list(Branches, Disj),
                    Goals = [Disj]
              ; build_call_or_partial(Fun, AllAVs, Out, Inner, [], Goals))
          %Literals (numbers, strings, etc.), known non-function atom => data:
          ; ( atomic(HV), \+ atom(HV) ; atom(HV), \+ fun(HV) ) -> Out = [HV|AVs],
                                                                  Goals = Inner
          %Plain data list: evaluate inner fun-sublists
          ; is_list(HV) -> eval_data_term(HV, Gd, HV1),
                           append(Inner, Gd, Goals),
                           Out = [HV1|AVs]
          %Unknown head (var/compound) => runtime dispatch:
          ; append(Inner, [reduce([HV|AVs], Out)], Goals) )).

%Generate actual function call or partial if arity not complete:
build_call_or_partial(Fun, AVs, Out, Inner, Extra, Goals) :- length(AVs, N),
                                                             Arity is N + 1,
                                                             ( maybe_specialize_call(Fun, AVs, Out, Goal)
                                                               -> append(Inner, [Goal|Extra], Goals)
                                                                ; ( ( current_predicate(Fun/Arity) ; catch(arity(Fun, Arity), _, fail) ),
                                                                     \+ ( current_op(_, _, Fun), Arity =< 2 ) )
                                                                  -> append(AVs, [Out], Args),
                                                                     Goal =.. [Fun|Args],
                                                                     append(Inner, [Goal|Extra], Goals)
                                                                   ; Out = partial(Fun, AVs),
                                                                     append(Inner, Extra, Goals) ).

%Type function call generation, returns function call plus typechecks for input and output:
typed_functioncall_branch(Fun, TypeChain, T, GsH, IsPartial, Bound, Out, BranchGoal) :-
    TypeChain = [->|Xs],
    append(ArgTypes, [OutType], Xs),
    translate_args_by_type(T, ArgTypes, GsT2, AVsTmp0),
    ( IsPartial -> append(Bound, AVsTmp0, AVsTmp) ; AVsTmp = AVsTmp0 ),
    append(GsH, GsT2, InnerTmp),
    ( (OutType == '%Undefined%' ; OutType == 'Atom')
       -> Extra = [] ; Extra = [('get-type'(Out, OutType) *-> true ; 'get-metatype'(Out, OutType))] ),
    build_call_or_partial(Fun, AVsTmp, Out, InnerTmp, Extra, GoalsList),
    goals_list_to_conj(GoalsList, BranchGoal).


%Selectively apply translate_args for non-Expression args while Expression args stay as data input:
translate_args_by_type([], _, [], []) :- !.
translate_args_by_type([A|As], [T|Ts], GsOut, [AV|AVs]) :-
                      ( T == 'Expression' -> AV = A, GsA = []
                                           ; translate_expr(A, GsA1, AV),
                                             ( (T == '%Undefined%' ; T == 'Atom')
                                               -> GsA = GsA1
                                                ; append(GsA1, [('get-type'(AV, T) *-> true ; 'get-metatype'(AV, T))], GsA))),
                                             translate_args_by_type(As, Ts, GsRest, AVs),
                                             append(GsA, GsRest, GsOut).

%Handle data list:
eval_data_term(X, [], X) :- (var(X); atomic(X)), !.
eval_data_term([F|As], Goals, Val) :- ( atom(F), fun(F) -> translate_expr([F|As], Goals, Val)
                                                         ; eval_data_list([F|As], Goals, Val) ).

%Handle data list entry:
eval_data_list([], [], []).
eval_data_list([E|Es], Goals, [V|Vs]) :- ( is_list(E) -> eval_data_term(E, G1, V) ; V = E, G1 = [] ),
                                         eval_data_list(Es, G2, Vs),
                                         append(G1, G2, Goals).


%Convert let* to recusrive let:
letstar_to_rec_let([[Pat,Val]],Body,[let,Pat,Val,Body]).
letstar_to_rec_let([[Pat,Val]|Rest],Body,[let,Pat,Val,Out]) :- letstar_to_rec_let(Rest,Body,Out).

%Patterns: variables, atoms, numbers, lists:
translate_pattern(X, X) :- var(X), !.
translate_pattern(X, X) :- atomic(X), !.
translate_pattern([H|T], [P|Ps]) :- !, translate_pattern(H, P),
                                       translate_pattern(T, Ps).

% Constructs the goal for a single branch of an if-then-else/case.
build_branch(true, Val, Out, (Out = Val)) :- !.
build_branch(Con, Val, Out, Goal) :- var(Val) -> Val = Out, Goal = Con
                                               ; Goal = (Val = Out, Con).

%Translate case expression recursively into nested if:
translate_case([[K,VExpr]|Rs], Kv, Out, Goal, KGo) :- translate_expr_to_conj(VExpr, ConV, VOut),
                                                      constrain_args(K, Kc, Gc),
                                                      build_branch(ConV, VOut, Out, Then),
                                                      ( Rs == [] -> Goal = ((Kv = Kc) -> Then), KGi=[]
                                                                  ; translate_case(Rs, Kv, Out, Next, KGi),
                                                                    Goal = ((Kv = Kc) -> Then ; Next) ),
                                                      append([Gc,KGi], KGo).

%Translate arguments recursively:
translate_args([], [], []).
translate_args([X|Xs], Goals, [V|Vs]) :- translate_expr(X, G1, V),
                                         translate_args(Xs, G2, Vs),
                                         append(G1, G2, Goals).

%Build A ; B ; C ... from a list:
disj_list([G], G).
disj_list([G|Gs], (G ; R)) :- disj_list(Gs, R).

%Build one disjunct per branch: (Conj, Out = Val):
build_superpose_branches([], _, []).
build_superpose_branches([E|Es], Out, [B|Bs]) :- translate_expr_to_conj(E, Conj, Val),
                                                 build_branch(Conj, Val, Out, B),
                                                 build_superpose_branches(Es, Out, Bs).

%Build hyperpose branch as a goal list for concurrent_maplist to consume:
build_hyperpose_branches([], []).
build_hyperpose_branches([E|Es], [(Goal, Res)|Bs]) :- translate_expr_to_conj(E, Goal, Res),
                                                      build_hyperpose_branches(Es, Bs).

%Like membercheck but with direct equality rather than unification
memberchk_eq(V, [H|_]) :- V == H, !.
memberchk_eq(V, [_|T]) :- memberchk_eq(V, T).

%Generate readable lambda name:
next_lambda_name(Name) :- ( catch(nb_getval(lambda_counter, Prev), _, Prev = 0) ),
                          N is Prev + 1,
                          nb_setval(lambda_counter, N),
                          format(atom(Name), 'lambda_~d', [N]).


%% ======== filereader.pl ========
:- use_module(library(readutil)). % read_file_to_string/3
:- catch(use_module(library(pcre)), _, true). % re_replace/4
%% [WASM PATCH] silent flag set in bundle header

%Read Filename into string S and process it (S holds MeTTa code):
load_metta_file(Filename, Results) :- load_metta_file(Filename, Results, '&self').
load_metta_file(Filename, Results, Space) :- read_file_to_string(Filename, S, []),
                                             process_metta_string(S, Results, Space).

%Extract function definitions, call invocations, and S-expressions part of &self space:
process_metta_string(S, Results) :- process_metta_string(S, Results, '&self').
process_metta_string(S, Results, Space) :- string_codes(S, Cs),
                                           strip(Cs, 0, Codes),
                                           phrase(top_forms(Forms, 1), Codes),
                                           maplist(parse_form, Forms, ParsedForms),
                                           maplist(process_form(Space), ParsedForms, ResultsList), !,
                                           append(ResultsList, Results).

%First pass to convert MeTTa to Prolog Terms and register functions:
parse_form(form(S), parsed(T, S, Term)) :- sread(S, Term),
                                           ( Term = [=, [F|W], _], atom(F) -> register_fun(F), length(W, N), Arity is N + 1, assertz(arity(F,Arity)), T=function
                                                                            ; T=expression ).
parse_form(runnable(S), parsed(runnable, S, Term)) :- sread(S, Term).

%Second pass to compile / run / add the Terms:
process_form(Space, parsed(expression, _, Term), []) :- 'add-atom'(Space, Term, true),
                                                        ( silent(true) -> true ; swrite(Term,STerm),
                                                                                 format("\e[33m--> metta sexpr -->~n\e[36m~w~n", [STerm]),
                                                                                 format("\e[33m^^^^^^^^^^^^^^^^^^^~n\e[0m") ).
process_form(_, parsed(runnable, FormStr, Term), Result) :- translate_expr([collapse, Term], Goals, Result),
                                                            ( silent(true) -> true ; format("\e[33m--> metta runnable  -->~n\e[36m!~w~n\e[33m-->  prolog goal  -->\e[35m ~n", [FormStr]),
                                                                                     forall(member(G, Goals), portray_clause((:- G))),
                                                                                     format("\e[33m^^^^^^^^^^^^^^^^^^^^^^^~n\e[0m") ),
                                                            call_goals(Goals).
process_form(Space, parsed(function, FormStr, Term), []) :- add_sexp(Space, Term),
                                                            translate_clause(Term, Clause),
                                                            assertz(Clause, Ref),
                                                            assertz(translated_from(Ref, Term)),
                                                            ( silent(true) -> true ; format("\e[33m--> metta function -->~n\e[36m~w~n\e[33m--> prolog clause -->~n\e[32m", [FormStr]),
                                                                                     clause(Head, Body, Ref),
                                                                                     ( Body == true -> Show = Head; Show = (Head :- Body) ),
                                                                                     portray_clause(current_output, Show),
                                                                                     format("\e[33m^^^^^^^^^^^^^^^^^^^^^^~n\e[0m") ).
process_form(_, In, _) :- format(atom(Msg), "failed to process form: ~w", [In]), throw(error(syntax_error(Msg), none)).

%Like blanks but counts newlines:
newlines(C0, C2) --> blanks_to_nl, !, {C1 is C0+1}, newlines(C1,C2).
newlines(C, C) --> blanks.

%Collect characters until all parentheses are balanced (depth 0), accumulating codes, and also counting newlines:
grab_until_balanced(D, Acc, Cs, LC0, LC2, InS) --> [C], { ( C=0'" -> InS1 is 1-InS ; InS1 = InS ),
                                                                     ( InS = 0 -> ( C=0'( -> D1 is D+1
                                                                                           ; C=0') -> D1 is D-1
                                                                                                    ; D1 = D )
                                                                                ; D1 = D ),
                                                                     Acc1=[C|Acc],
                                                                     ( C=10 -> LC1 is LC0+1 ; LC1 = LC0 ) },
                                                          ( { D1=:=0, InS1=0 } -> { reverse(Acc1,Cs) , LC2 = LC1 }
                                                                                ; grab_until_balanced(D1,Acc1,Cs,LC1,LC2,InS1) ).

%Read a balanced (...) block if available, turn into string, then continue with rest, ignoring comments:
top_forms([],_) --> blanks, eos.
top_forms([Term|Fs], LC0) --> newlines(LC0, LC1),
                              ( "!" -> {Tag = runnable} ; {Tag = form} ),
                              ( "(" -> [] ; string_without("\n", Rest), { format(atom(Msg), "expected '(' or '!(', line ~w:~n~s", [LC1, Rest]), throw(error(syntax_error(Msg), none)) } ),
                              ( grab_until_balanced(1, [0'(], Cs, LC1, LC2, 0)
                                -> { true } ; string_without("\n", Rest), { format(atom(Msg), "missing ')', starting at line ~w:~n~s", [LC1, Rest]), throw(error(syntax_error(Msg), none)) } ),
                              { string_codes(FormStr, Cs), Term =.. [Tag, FormStr] },
                              top_forms(Fs, LC2).

%Strip off code that is commented out, while tracking when inside of string:
strip([], _, []).
strip([0'"|R], 0, [0'"|O]) :- !, strip(R, 1, O).
strip([0'"|R], 1, [0'"|O]) :- !, strip(R, 0, O).
strip([0'\n|R], In, [0'\n|O]) :- !, strip(R, In, O).
strip([0';|R], 0, Out) :- !, append(_, [0'\n|Rest], R), strip(Rest, 0, Out).
strip([C|R], In, [C|O]) :- strip(R, In, O).


%% ======== metta.pl ========
%%%%%%%%%% Dependencies %%%%%%%%%%
library(X, Path) :- library_path(Base), atomic_list_concat([Base, '/', X], Path).
library(X, Y, Path) :- library_path(Base), atomic_list_concat([Base, '/../', X, '/', Y], Path).
:- prolog_load_context(directory, Source),
   directory_file_path(Source, '..', Parent),
   directory_file_path(Parent, 'lib', LibPath),
   asserta(library_path(LibPath)).
:- catch(autoload(library(uuid)), _, true).
:- use_module(library(random)).
:- catch(use_module(library(janus)), _, true).
:- use_module(library(error)).
:- use_module(library(listing)).
:- use_module(library(aggregate)).
:- catch(use_module(library(thread)), _, true).
:- use_module(library(lists)).
:- use_module(library(yall), except([(/)/3])).
:- use_module(library(apply)).
:- use_module(library(apply_macros)).
:- catch(use_module(library(process)), _, true).
:- use_module(library(filesex)).
%% [WASM PATCH] Module loading handled by bundle concatenation

%%%%%%%%%% Standard Library for MeTTa %%%%%%%%%%

%%% Representation and parsing conversions: %%%
id(X, X).
repr(Term, R) :- swrite(Term, R).
repra(Term, R) :- term_to_atom(Term, R).
parse(Str, R) :- sread(Str, R).

%%% Arithmetic & Comparison: %%%
'+'(A,B,R)  :- R is A + B.
'-'(A,B,R)  :- R is A - B.
'*'(A,B,R)  :- R is A * B.
'/'(A,B,R)  :- R is A / B.
'%'(A,B,R)  :- R is A mod B.
'<'(A,B,R)  :- (A<B -> R=true ; R=false).
'>'(A,B,R)  :- (A>B -> R=true ; R=false).
'=='(A,B,R) :- (A==B -> R=true ; R=false).
'!='(A,B,R) :- (A==B -> R=false ; R=true).
'='(A,B,R) :-  (A=B -> R=true ; R=false).
'=?'(A,B,R) :- (\+ \+ A=B -> R=true ; R=false).
'=alpha'(A,B,R) :- (A =@= B -> R=true ; R=false).
'=@='(A,B,R) :- (A =@= B -> R=true ; R=false).
'<='(A,B,R) :- (A =< B -> R=true ; R=false).
'>='(A,B,R) :- (A >= B -> R=true ; R=false).
min(A,B,R)  :- R is min(A,B).
max(A,B,R)  :- R is max(A,B).
exp(Arg,R) :- R is exp(Arg).
:- catch(use_module(library(clpfd)), _, true).
'#+'(A, B, R) :- R #= A + B.
'#-'(A, B, R) :- R #= A - B.
'#*'(A, B, R) :- R #= A * B.
'#div'(A, B, R) :- R #= A div B.
'#//'(A, B, R) :- R #= A // B.
'#mod'(A, B, R) :- R #= A mod B.
'#min'(A, B, R) :- R #= min(A,B).
'#max'(A, B, R) :- R #= max(A,B).
'#<'(A, B, true)  :- A #< B, !.
'#<'(_, _, false).
'#>'(A, B, true)  :- A #> B, !.
'#>'(_, _, false).
'#='(A, B, true)  :- A #= B, !.
'#='(_, _, false).
'#\\='(A, B, true)  :- A #\= B, !.
'#\\='(_, _, false).
'pow-math'(A, B, Out) :- Out is A ** B.
'sqrt-math'(A, Out)   :- Out is sqrt(A).
'abs-math'(A, Out)    :- Out is abs(A).
'log-math'(Base, X, Out) :- Out is log(X) / log(Base).
'trunc-math'(A, Out)  :- Out is truncate(A).
'ceil-math'(A, Out)   :- Out is ceil(A).
'floor-math'(A, Out)  :- Out is floor(A).
'round-math'(A, Out)  :- Out is round(A).
'sin-math'(A, Out)  :- Out is sin(A).
'cos-math'(A, Out)  :- Out is cos(A).
'tan-math'(A, Out)  :- Out is tan(A).
'asin-math'(A, Out) :- Out is asin(A).
'acos-math'(A, Out) :- Out is acos(A).
'atan-math'(A, Out) :- Out is atan(A).
'isnan-math'(A, Out) :- ( A =:= A -> Out = false ; Out = true ).
'isinf-math'(A, Out) :- ( A =:= 1.0Inf ; A =:= -1.0Inf -> Out = true ; Out = false ).
'min-atom'(List, Out) :- min_list(List, Out).
'max-atom'(List, Out) :- max_list(List, Out).

%%% Random Generators: %%%
'random-int'(Min, Max, Result) :- random_between(Min, Max, Result).
'random-int'('&rng', Min, Max, Result) :- random_between(Min, Max, Result).
'random-float'(Min, Max, Result) :- random(R), Result is Min + R * (Max - Min).
'random-float'('&rng', Min, Max, Result) :- random(R), Result is Min + R * (Max - Min).

%%% Boolean Logic: %%%
bool(true).
bool(false).
and(A,B,C) :- bool(A), bool(B), ( A == true -> C = B ; A == false -> C = false ).
or(A,B,C) :- bool(A), bool(B), ( A == true -> C = true ; A == false -> C = B ).
not(A,B) :- bool(A), ( A == true -> B = false ; A == false -> B = true ).
xor(A,B,C) :- bool(A), bool(B), ( A == B -> C = false ; C = true ).
implies(A,B,C) :- bool(A), bool(B), ( A == true -> ( B == true  -> C = true ; B == false -> C = false )
                                                 ; A == false -> C = true ).

%%% Nondeterminism: %%%
superpose(L,X) :- member(X,L).
empty(_) :- fail.

%%% Lists / Tuples: %%%
'cons-atom'(H, T, [H|T]).
'decons-atom'([H|T], [H|[T]]).
'first-from-pair'([A, _], A).
first([A, _], A).
'second-from-pair'([_, A], A).
'unique-atom'(A, B) :- list_to_set(A, B).
'sort-atom'(List, Sorted) :- msort(List, Sorted).
'size-atom'(List, Size) :- length(List, Size).
'car-atom'([H|_], H).
'cdr-atom'([_|T], T).
decons([H|T], [H|[T]]).
cons(H, T, [H|T]).
'index-atom'(List, Index, Elem) :- nth0(Index, List, Elem).
member(X, L, true) :- member(X, L).
'is-member'(X, List, true) :- member(X, List).
'is-member'(X, List, false) :- \+ member(X, List).
'exclude-item'(A, L, R) :- exclude(==(A), L, R).

%Multisets:
'subtraction-atom'([], _, []).
'subtraction-atom'([H|T], B, Out) :- ( select(H, B, BRest) -> 'subtraction-atom'(T, BRest, Out)
                                                            ; Out = [H|Rest],
                                                              'subtraction-atom'(T, B, Rest) ).
'union-atom'(A, B, Out) :- append(A, B, Out).
'intersection-atom'(A, B, Out) :- intersection(A, B, Out).

%%% Type system: %%%
get_function_type([F|Args], T) :- nonvar(F), match('&self', [':',F,[->|Ts]], _, _),
                                  append(As,[T],Ts),
                                  maplist('get-type',Args,As).

:- dynamic 'get-type'/2.
'get-type'(X, T) :- (get_type_candidate(X, T) *-> true ; T = '%Undefined%' ).
get_type_candidate(X, 'Number')   :- number(X), !.
get_type_candidate(X, _) :- var(X), !.
get_type_candidate(X, 'String')   :- string(X), !.
get_type_candidate(true, 'Bool')  :- !.
get_type_candidate(false, 'Bool') :- !.
get_type_candidate(X, T) :- get_function_type(X,T).
get_type_candidate(X, T) :- \+ get_function_type(X, _),
                            is_list(X),
                            maplist('get-type', X, T).
get_type_candidate(X, T) :- match('&self', [':',X,T], T, _).
'get-metatype'(X, 'Variable') :- var(X), !.
'get-metatype'(X, 'Grounded') :- number(X), !.
'get-metatype'(X, 'Grounded') :- string(X), !.
'get-metatype'(true,  'Grounded') :- !.
'get-metatype'(false, 'Grounded') :- !.
'get-metatype'(X, 'Grounded') :- atom(X), fun(X), !.  % e.g., '+' is a registered fun/1
'get-metatype'(X, 'Expression') :- is_list(X), !.     % e.g., (+ 1 2), (a b)
'get-metatype'(X, 'Symbol') :- atom(X), !.            % e.g., a

'is-var'(A,R) :- var(A) -> R=true ; R=false.
'is-expr'(A,R) :- is_list(A) -> R=true ; R=false.
'is-space'(A,R) :- atom(A), atom_concat('&', _, A) -> R=true ; R=false.

%%% Diagnostics / Testing: %%%
'println!'(Arg, true) :- swrite(Arg, RArg),
                         format('~w~n', [RArg]).

'readln!'(Out) :- read_line_to_string(user_input, Str),
                  sread(Str, Out).

test(A,B,true) :- (A =@= B -> true ; halt(1)).

assert(Goal, true) :- ( call(Goal) -> true
                                    ; swrite(Goal, RG),
                                      format("Assertion failed: ~w~n", [RG]),
                                      halt(1) ).

%%% Time Retrieval: %%%
'current-time'(Time) :- get_time(Time).
'format-time'(Format, TimeString) :- get_time(Time), format_time(atom(TimeString), Format, Time).

%%% Python bindings: %%%
'py-call'(SpecList, Result) :- 'py-call'(SpecList, Result, []).
'py-call'([Spec|Args], Result, Opts) :- ( string(Spec) -> atom_string(A, Spec) ; A = Spec ),
                                        must_be(atom, A),
                                        ( sub_atom(A, 0, 1, _, '.')         % ".method"
                                          -> sub_atom(A, 1, _, 0, Fun),
                                             Args = [Obj|Rest],
                                             ( Rest == []
                                               -> compound_name_arguments(Meth, Fun, [])
                                                ; Meth =.. [Fun|Rest] ),
                                             py_call(Obj:Meth, Result, Opts)
                                           ; atomic_list_concat([M,F], '.', A) % "mod.fun"
                                             -> ( Args == []
                                                  -> compound_name_arguments(Call0, F, [])
                                                   ; Call0 =.. [F|Args] ),
                                                py_call(M:Call0, Result, Opts)
                                              ; ( Args == []                      % bare "fun"
                                                  -> compound_name_arguments(Call0, A, [])
                                                   ; Call0 =.. [A|Args] ),
                                                py_call(builtins:Call0, Result, Opts) ).

%%% States: %%%
'bind!'(A, ['new-state', B], C) :- 'change-state!'(A, B, C).
'change-state!'(Var, Value, true) :- nb_setval(Var, Value).
'get-state'(Var, Value) :- nb_getval(Var, Value).

%%% Eval: %%%
eval(C, Out) :- translate_expr(C, Goals, Out),
                call_goals(Goals).

call_goals([]).
call_goals([G|Gs]) :- call(G), 
                      call_goals(Gs).

%%% Higher-Order Functions: %%%
'foldl-atom'([], Acc, _Func, Acc).
'foldl-atom'([H|T], Acc0, Func, Out) :- reduce([Func,Acc0,H], Acc1),
                                        'foldl-atom'(T, Acc1, Func, Out).

'map-atom'([], _Func, []).
'map-atom'([H|T], Func, [R|RT]) :- reduce([Func,H], R),
                                   'map-atom'(T, Func, RT).

'filter-atom'([], _Func, []).
'filter-atom'([H|T], Func, Out) :- ( reduce([Func,H], true) -> Out = [H|RT]
                                                             ; Out = RT ),
                                   'filter-atom'(T, Func, RT).

%%% Prolog interop: %%%
argv(K, Arg) :- current_prolog_flag(argv, Argv), nth0(K, Argv, A), ( atom_number(A, N) -> Arg = N ; Arg = A ).
import_prolog_function(N, true) :- register_fun(N).
'Predicate'([F|Args], Term) :- Term =.. [F|Args].
callPredicate(G, true) :- call(G).
assertzPredicate(G, true) :- assertz(G).
assertaPredicate(G, true) :- asserta(G).
retractPredicate(G, true) :- retract(G), !.
retractPredicate(_, false).

%%% Library / Import: %%%
ensure_metta_ext(Path, Path) :- file_name_extension(_, metta, Path), !.
ensure_metta_ext(Path, PathWithExt) :- file_name_extension(Path, metta, PathWithExt).

'import!'(Space, File, true) :- catch(importer_helper(Space, File), _, fail).
importer_helper(Space, File) :- atom_string(File, SFile),
                                working_dir(Base),
                                ( file_name_extension(ModPath, 'py', SFile)
                                  -> absolute_file_name(SFile, Path, [relative_to(Base)]),
                                     file_directory_name(Path, Dir),
                                     file_base_name(ModPath, ModuleName),
                                     py_call(sys:path:append(Dir), _),
                                     py_call(builtins:'__import__'(ModuleName), _)
                                   ; ( Path = SFile ; atomic_list_concat([Base, '/', SFile], Path) ),
                                     ensure_metta_ext(Path, PathWithExt),
                                     exists_file(PathWithExt), !,
                                     load_metta_file(PathWithExt, _, Space) ).

:- dynamic translator_rule/1.
'add-translator-rule!'(HV, true) :- ( translator_rule(HV)
                                      -> true ; assertz(translator_rule(HV)) ).

'remove-translator-rule!'(HV, true) :- retractall(translator_rule(HV)).

%%% Registration: %%%
:- dynamic fun/1.
register_fun(N) :- (fun(N) -> true ; assertz(fun(N))).
:- maplist(register_fun, [superpose, empty, let, 'let*', '+','-','*','/', '%', min, max, 'change-state!', 'get-state', 'bind!',
                          '<','>','==', '!=', '=', '=?', '<=', '>=', and, or, xor, implies, not, sqrt, exp, log, cos, sin,
                          'first-from-pair', 'second-from-pair', 'car-atom', 'cdr-atom', 'unique-atom',
                          repr, repra, parse, 'println!', 'readln!', test, assert, 'mm2-exec', atom_concat, atom_chars, copy_term, term_hash,
                          foldl, first, last, append, length, 'size-atom', sort, msort, member, 'is-member', 'exclude-item', list_to_set, maplist, eval, reduce, 'import!',
                          'add-atom', 'remove-atom', 'get-atoms', match, 'is-var', 'is-expr', 'is-space', 'get-mettatype',
                          decons, 'decons-atom', 'py-call', 'get-type', 'get-metatype', '=alpha', concat, sread, cons, reverse,
                          '#+','#-','#*','#div','#//','#mod','#min','#max','#<','#>','#=','#\\=','set_hook',
                          'union-atom', 'cons-atom', 'intersection-atom', 'subtraction-atom', 'index-atom', id,
                          'pow-math', 'sqrt-math', 'sort-atom','abs-math', 'log-math', 'trunc-math', 'ceil-math',
                          'floor-math', 'round-math', 'sin-math', 'cos-math', 'tan-math', 'asin-math','random-int','random-float',
                          'acos-math', 'atan-math', 'isnan-math', 'isinf-math', 'min-atom', 'max-atom',
                          'foldl-atom', 'map-atom', 'filter-atom','current-time','format-time', library, exists_file,
                          import_prolog_function, 'Predicate', callPredicate, assertaPredicate, assertzPredicate, retractPredicate,
                          'add-translator-rule!', 'remove-translator-rule!', argv]).


%% ======== WASM Browser Wrapper ========

metta_exec(Input, Output) :-
    catch(
        (process_metta_string(Input, Results),
         swrite(Results, Output)),
        Error,
        (term_to_atom(Error, Output)
    )).

metta_run(Input) :-
    catch(
        (process_metta_string(Input, Results),
         forall(member(R, Results),
                (swrite(R, SR), format("~w~n", [SR])))),
        Error,
        (term_to_atom(Error, EStr), format("Error: ~w~n", [EStr])
    )).
