/*
 * CS250
 *
 * simple.y: simple parser for the simple "C" language
 * 
 * (C) Copyright Gustavo Rodriguez-Rivera grr@purdue.edu
 *
 * IMPORTANT: Do not post in Github or other public repository
 */

%token	<string_val> WORD

%token 	NOTOKEN LPARENT RPARENT LBRACE RBRACE LCURLY RCURLY COMA SEMICOLON EQUAL STRING_CONST LONG LONGSTAR VOID CHARSTAR CHARSTARSTAR INTEGER_CONST AMPERSAND OROR ANDAND EQUALEQUAL NOTEQUAL LESS GREAT LESSEQUAL GREATEQUAL PLUS MINUS TIMES DIVIDE PERCENT IF ELSE WHILE DO FOR CONTINUE BREAK RETURN

%union	{
		char   *string_val;
		int nargs;
		int my_nlabel;
	}

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int yylex();
int yyerror(const char * s);

extern int line_number;
const char * input_file;
char * asm_file;
FILE * fasm;

#define MAX_ARGS 5
int nargs;
char * args_table[MAX_ARGS];

#define MAX_GLOBALS 100
int nglobals = 0;
char * global_vars_table[MAX_GLOBALS];
int global_vars_types_table[MAX_GLOBALS];

#define MAX_LOCALS 32
int nlocals = 0;
char * local_vars_table[MAX_LOCALS];
int local_vars_types_table[MAX_LOCALS];

#define MAX_STRINGS 100
int nstrings = 0;
char * string_table[MAX_STRINGS];

char *regStk[]={ "rbx", "r10", "r13", "r14", "r15"};
char *smolStk[] = { "bl", "r10b", "r13b", "r14b", "r15b"};
char nregStk = sizeof(regStk)/sizeof(char*);

char *regArgs[]={ "rdi", "rsi", "rdx", "rcx", "r8", "r9"};
char nregArgs = sizeof(regArgs)/sizeof(char*);

int top = 0;

int nargs =0;
 
int nlabelloops = 0;

int nlabelif = 0;

int nlabelexpr = 0;

int arr_var_type;


%}

%%

goal:	program
	;

program :
        function_or_var_list;

function_or_var_list:
        function_or_var_list function
        | function_or_var_list global_var
        | /*empty */
	;

function:
         var_type WORD
         {
		 fprintf(fasm, "\t.text\n");
		 fprintf(fasm, ".globl %s\n", $2);
		 fprintf(fasm, "%s:\n", $2);

		 fprintf(fasm, "\t# Save Frame pointer\n");
		 fprintf(fasm, "\tpushq %%rbp\n");
         fprintf(fasm, "\tmovq %%rsp,%%rbp\n");

		 fprintf(fasm, "\tsubq $256, %%rsp\n");												/*reserving space in stack for function*/

		 fprintf(fasm, "# Save registers. \n");
		 fprintf(fasm, "# Push one extra to align stack to 16bytes\n");
         fprintf(fasm, "\tpushq %%rbx\n");
		 fprintf(fasm, "\tpushq %%rbx\n");
		 fprintf(fasm, "\tpushq %%r10\n");
		 fprintf(fasm, "\tpushq %%r13\n");
		 fprintf(fasm, "\tpushq %%r14\n");
		 fprintf(fasm, "\tpushq %%r15\n");
		 						
		 nlocals = 0;
		 top = 0;

	 }
	 // can add the arguments to the stack as the arguments to the function are being parsed
	 LPARENT arguments {

		fprintf(fasm, "\t#Saving arguments to the stack\n");

		for (int i = 0; i < nlocals; i++) {
			fprintf(fasm, "\tmovq %%%s, -%d(%%rbp)\n", regArgs[i], 8*(i + 1));
		}
		
	 } RPARENT compound_statement
    {	
		
		fprintf(fasm, "# Restore registers\n");
		fprintf(fasm, "\tpopq %%r15\n");
		fprintf(fasm, "\tpopq %%r14\n");
		fprintf(fasm, "\tpopq %%r13\n");
		fprintf(fasm, "\tpopq %%r10\n");
		fprintf(fasm, "\tpopq %%rbx\n");
		fprintf(fasm, "\tpopq %%rbx\n");

		fprintf(fasm, "\taddq $256, %%rsp\n");													/*restoring space in stack*/

		fprintf(fasm, "\tleave\n");
		fprintf(fasm, "\tret\n");
    }
	;

arg_list:
         arg
         | arg_list COMA arg
	 ;

arguments:
         arg_list
	 | /*empty*/
	 ;

arg: var_type WORD {
	char * id = $<string_val>2;
	local_vars_table[nlocals]=id;											// adding arguments to local_vars_table
	local_vars_types_table[nlocals] = arr_var_type;							// storing type of local variable
  	nlocals++;
}

global_var: 
        var_type global_var_list SEMICOLON;

global_var_list: WORD {
	fprintf(fasm, "\t.data\n");
	fprintf(fasm, "\t.comm %s,8\n", $1);

	char * id = $<string_val>1;
	global_vars_table[nglobals]=id;											// adding global variables to global_vars_table
	global_vars_types_table[nglobals] = arr_var_type;						// storing type of global variable
	nglobals++;

}
| global_var_list COMA WORD {
	fprintf(fasm, "\t.comm %s,8\n", $3);

	char * id = $<string_val>3;
	global_vars_table[nglobals]=id;
	global_vars_types_table[nglobals] = arr_var_type;
	nglobals++;


}
;

var_type: CHARSTAR {arr_var_type = 0;} | CHARSTARSTAR {arr_var_type = 1;} | LONG | LONGSTAR {arr_var_type = 1;} | VOID;

assignment:
         WORD EQUAL expression {
			int pos = -1;
			char *id = $1;

			for (int i = 0; i < nlocals; i++) {											/*looking for local variable*/
				if (strcmp(local_vars_table[i], id) == 0) {
					pos = i;
					break;
				}
			}

			if (pos == -1) {
				fprintf(fasm, "\t# assigning val to global variable\n");
				fprintf(fasm, "\tmovq %%rbx, %s\n", $1);								
			} else {
				fprintf(fasm, "\t# saving local variable to stack\n");
				fprintf(fasm, "\tmovq %%rbx, -%d(%%rbp)\n", 8*(pos+1));					
			}
			top = 0;
		 }
	 | WORD LBRACE expression RBRACE {
		int pos = -1;
		char *id = $1;

		for (int i = 0; i < nlocals; i++) {											/*looking for local variable*/
			if (strcmp(local_vars_table[i], id) == 0) {
				pos = i;
				break;
			}
		}

		int array_type;

		if (pos == -1) {
			int glob_pos = -1;
			// look for global var type
			for (int i = 0; i < nglobals; i++) {
		 		if (strcmp(global_vars_table[i], id)) {
			 		glob_pos = i;
					break;
		 		}
	 		}

			array_type = global_vars_types_table[glob_pos];


		} else {
			// look for local var type
			array_type = local_vars_types_table[pos];

		}

		if (array_type != 0) {															// if a not a char array, offset is 8
			fprintf(fasm, "\timulq $8, %%%s\n", regStk[top-1]);
		} 

		if (pos == -1) {
			fprintf(fasm, "\t# assignment to global variable\n");
			fprintf(fasm, "\tmovq %s,%%%s\n", id, regStk[top]);								/*assignment to global variable*/
		} else {
			fprintf(fasm, "\t# assignment to local variable\n"); 
			fprintf(fasm, "\tmovq -%d(%%rbp), %%%s\n", 8*(pos+1), regStk[top]); 			/* assignment to local variable */
		}

		top++;

		fprintf(fasm, "\taddq %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
		top--;


	 } EQUAL expression {
		fprintf(fasm, "\tmovq %%%s, (%%%s)\n", regStk[top-1], regStk[top-2]);		// assigns val to index in array
		top = top - 2;	

	 }
	 ;

call :
         WORD LPARENT  call_arguments RPARENT {
		 char * funcName = $<string_val>1;
		 int nargs = $<nargs>3;
		 int i;
		 fprintf(fasm,"     # func=%s nargs=%d\n", funcName, nargs);
     		 fprintf(fasm,"     # Move values from reg stack to reg args\n");
		 for (i=nargs-1; i>=0; i--) {
			top--;
			fprintf(fasm, "\tmovq %%%s, %%%s\n",
			  regStk[top], regArgs[i]);
		 }
		 if (!strcmp(funcName, "printf")) {
			 // printf has a variable number of arguments
			 // and it need the following
			 fprintf(fasm, "\tmovl    $0, %%eax\n");
		 }
		 fprintf(fasm, "\tcall %s\n", funcName);
		 fprintf(fasm, "\tmovq %%rax, %%%s\n", regStk[top]);
		 top++;
         }
      ;

call_arg_list:
         expression {
		$<nargs>$=1;
	 }
         | call_arg_list COMA expression {
		$<nargs>$++;
	 }

	 ;

call_arguments:
         call_arg_list { $<nargs>$=$<nargs>1; }
	 | /*empty*/ { $<nargs>$=0;}
	 ;

expression :
         logical_or_expr
	 ;

logical_or_expr:
         logical_and_expr
	 | logical_or_expr OROR logical_and_expr {

		fprintf(fasm, "\torq %%%s, %%%s\n", regStk[top - 1], regStk[top - 2]);		
		top--;																		
	 }
	 ;

logical_and_expr:
         equality_expr
	 | logical_and_expr ANDAND equality_expr {

		fprintf(fasm, "\tandq %%%s, %%%s\n", regStk[top - 1], regStk[top - 2]);		
		top--;																		
	 }
	 ;

equality_expr:
         relational_expr
	 | equality_expr EQUALEQUAL relational_expr {

		fprintf(fasm, "\t # equality EQUALS expression\n");

		fprintf(fasm, "\tcmpq %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
		fprintf(fasm, "\tjne not_equal%d\n", nlabelexpr);
		fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-2]);
		fprintf(fasm, "\tjmp end%d\n", nlabelexpr);
		fprintf(fasm, "not_equal%d:\n", nlabelexpr);
		fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
		fprintf(fasm, "end%d:\n", nlabelexpr);

		nlabelexpr++;
		top--;
	 } 
	 | equality_expr NOTEQUAL relational_expr {
		fprintf(fasm, "\t # equality NOT-EQUALS expression\n");

		fprintf(fasm, "\tcmpq %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
		fprintf(fasm, "\tjne not_equal%d\n", nlabelexpr);
		fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
		fprintf(fasm, "\tjmp end%d\n", nlabelexpr);
		fprintf(fasm, "not_equal%d:\n", nlabelexpr);
		fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-2]);
		fprintf(fasm, "end%d:\n", nlabelexpr);

		nlabelexpr++;
		top--;
	 }
	 ;

relational_expr:
         additive_expr
	 | relational_expr LESS additive_expr {
		
		fprintf(fasm, "\n\t# relational LESS-THAN expresion\n");
		
		fprintf(fasm, "\tcmpq %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
		fprintf(fasm, "\tjl less_than%d\n", nlabelexpr);
		fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
		fprintf(fasm, "\tjmp end%d\n", nlabelexpr);
		fprintf(fasm, "less_than%d:\n", nlabelexpr);
		fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-2]);
		fprintf(fasm, "end%d:\n", nlabelexpr);
		
		nlabelexpr++;
		top--;

	 }
	 | relational_expr GREAT additive_expr {
		fprintf(fasm, "\n\t# relational GREATER-THAN expresion\n");
		
		fprintf(fasm, "\tcmpq %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
		fprintf(fasm, "\tjg greater_than%d\n", nlabelexpr);
		fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
		fprintf(fasm, "\tjmp end%d\n", nlabelexpr);
		fprintf(fasm, "greater_than%d:\n", nlabelexpr);
		fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-2]);
		fprintf(fasm, "end%d:\n", nlabelexpr);
		
		nlabelexpr++;
		top--;

	 }
	 | relational_expr LESSEQUAL additive_expr {
		fprintf(fasm, "\n\t# relational LESS-THAN-OR-EQUAL expresion\n");
		
		fprintf(fasm, "\tcmpq %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
		fprintf(fasm, "\tjle less_than_or_equal%d\n", nlabelexpr);
		fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
		fprintf(fasm, "\tjmp end%d\n", nlabelexpr);
		fprintf(fasm, "less_than_or_equal%d:\n", nlabelexpr);
		fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-2]);
		fprintf(fasm, "end%d:\n", nlabelexpr);
		
		nlabelexpr++;
		top--;

	 }
	 | relational_expr GREATEQUAL additive_expr {
		fprintf(fasm, "\n\t# relational GREATER-THAN-OR-EQUAL expresion\n");
		
		fprintf(fasm, "\tcmpq %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
		fprintf(fasm, "\tjge greater_than_or_equal%d\n", nlabelexpr);
		fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
		fprintf(fasm, "\tjmp end%d\n", nlabelexpr);
		fprintf(fasm, "greater_than_or_equal%d:\n", nlabelexpr);
		fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-2]);
		fprintf(fasm, "end%d:\n", nlabelexpr);
		
		nlabelexpr++;
		top--;

	 }
	 ;

additive_expr:
          multiplicative_expr
	  | additive_expr PLUS multiplicative_expr {
		
		if (top<nregStk) {
			fprintf(fasm, "\taddq %%%s,%%%s\n", regStk[top-1], regStk[top-2]);
			top--;
		}
	  }
	  | additive_expr MINUS multiplicative_expr {

		if (top<nregStk) {
			fprintf(fasm, "\tsubq %%%s,%%%s\n", regStk[top-1], regStk[top-2]);
			top--;
		}			
	  }
	  ;

multiplicative_expr:
          primary_expr
	  | multiplicative_expr TIMES primary_expr {

		if (top<nregStk) {
			fprintf(fasm, "\timulq %%%s,%%%s\n", regStk[top-1], regStk[top-2]);
			top--;
		}
          }
	  | multiplicative_expr DIVIDE primary_expr {
																						
		if (top<nregStk) {
			fprintf(fasm, "\tmovq $0, %%rdx\n");									
			fprintf(fasm, "\tmovq %%%s, %%rax\n", regStk[top-2]);					
			fprintf(fasm, "\tidivq %%%s\n", regStk[top - 1]);						
			fprintf(fasm, "\tmovq %%rax, %%%s\n", regStk[top-2]);					
			top--;
		}
		
	  }
	  | multiplicative_expr PERCENT primary_expr {	

			if (top<nregStk) {
			fprintf(fasm, "\tmovq $0, %%rdx\n");										
			fprintf(fasm, "\tmovq %%%s, %%rax\n", regStk[top-2]);					
			fprintf(fasm, "\tidivq %%%s\n", regStk[top - 1]);						
			fprintf(fasm, "\tmovq %%rdx, %%%s\n", regStk[top-2]);					
			top--;
		}

	  }
	  ;

primary_expr:
	  STRING_CONST {
		  // Add string to string table.
		  // String table will be produced later
		  string_table[nstrings]=$<string_val>1;
		  fprintf(fasm, "\t#top=%d\n", top);
		  fprintf(fasm, "\n\t# push string %s top=%d\n",
			  $<string_val>1, top);
		  if (top<nregStk) {
		  	fprintf(fasm, "\tmovq $string%d, %%%s\n", nstrings, regStk[top]);

			//fprintf(fasm, "\tmovq $%s,%%%s\n", 
				//$<string_val>1, regStk[top]);
			top++;
		  }
		  nstrings++;
	  }
      | call
	  | WORD {
		  
		  	char * id = $1;
			int pos = -1;

			for (int i = 0; i < nlocals; i++) {													/*looking for local variable*/
				if (strcmp(local_vars_table[i], id) == 0) {
					pos = i;
					break;
				}
			}

			if (pos == -1) {
				fprintf(fasm, "\t# assignment to global variable\n"); 
				fprintf(fasm, "\tmovq %s,%%%s\n", id, regStk[top]);								/*assignment to global variable*/
			} else {
				fprintf(fasm, "\t# assignment to local variable\n"); 
				fprintf(fasm, "\tmovq -%d(%%rbp), %%%s\n", 8*(pos+1), regStk[top]); 			/* assignment to local variable */
			}

		  top++;
	  }
	  | WORD LBRACE expression RBRACE {

		int pos = -1;
		char *id = $1;

		for (int i = 0; i < nlocals; i++) {											/*looking for local variable*/
			if (strcmp(local_vars_table[i], id) == 0) {
				pos = i;
				break;
			}
		}

		int array_type;

		if (pos == -1) {
			int glob_pos = -1;
			// look for global var type
			for (int i = 0; i < nglobals; i++) {
		 		if (strcmp(global_vars_table[i], id)) {
			 		glob_pos = i;
					break;
		 		}
	 		}

			array_type = global_vars_types_table[glob_pos];


		} else {
			// look for local var type
			array_type = local_vars_types_table[pos];

		}

		if (array_type != 0) {															// if a not a char array, offset is 8
			fprintf(fasm, "\timulq $8, %%%s\n", regStk[top-1]);
		} 

		if (pos == -1) {
			fprintf(fasm, "\t# assignment to global variable\n");
			fprintf(fasm, "\tmovq %s,%%%s\n", id, regStk[top]);								/*assignment to global variable*/
		} else {
			fprintf(fasm, "\t# assignment to local variable\n"); 
			fprintf(fasm, "\tmovq -%d(%%rbp), %%%s\n", 8*(pos+1), regStk[top]); 			/* assignment to local variable */
		}

		top++;

		fprintf(fasm, "\taddq %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
		top--;
		
		fprintf(fasm, "\tmovq (%%%s), %%%s\n", regStk[top-1], regStk[top-1]);
		

		// dealing with array for strlen and quicksort
		if (array_type == 0) {
			fprintf(fasm, "\tmovb %%%s, %%cl\n", smolStk[top-1]);							// need smolStk to keep track of current 0 byte registers available
		 	fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-1]);							
		 	fprintf(fasm, "\tmovb %%cl, %%%s\n", smolStk[top-1]);							// clearing top register to store bottom byte in order to compare it to 0 in while-loop 
		}

	
	  }
	  | AMPERSAND WORD {
			char * id = $<string_val>2;
			int pos = -1;

			for (int i = 0; i < nlocals; i++) {													/*looking for local variable*/
				if (strcmp(local_vars_table[i], id) == 0) {
					pos = i;
					break;
				}
			}

			if (pos == -1) {
				fprintf(fasm, "\tleaq %s,%%%s\n", id, regStk[top]);								/*load address to global variable*/
			} else { 
				fprintf(fasm, "\tleaq -%d(%%rbp), %%%s\n", 8*(pos+1), regStk[top]); 			/* load address to local variable */
			}

		  top++;

	  }
	  | INTEGER_CONST {
		  fprintf(fasm, "\n\t# push %s\n", $<string_val>1);
		  if (top<nregStk) {
			fprintf(fasm, "\tmovq $%s,%%%s\n", 
				$<string_val>1, regStk[top]);
			top++;
		  } else {
			fprintf(stderr, "Line %d: Register overflow\n", line_number);
			exit(1);
		  }
	  }
	  | LPARENT expression RPARENT
	  ;

compound_statement:
	 LCURLY statement_list RCURLY
	 ;

statement_list:
         statement_list statement
	 | /*empty*/
	 ;

local_var:
        var_type local_var_list SEMICOLON;

local_var_list: 
		WORD {
			local_vars_table[nlocals] = $<string_val>1;									/*first local variable*/
			local_vars_types_table[nlocals] = arr_var_type;
			nlocals++;
		}
        | local_var_list COMA WORD {
			local_vars_table[nlocals] = $<string_val>3;									/*second local variable and onward*/		
			local_vars_types_table[nlocals] = arr_var_type;	
			nlocals++;
		}
        ;

statement:
         assignment SEMICOLON
	 | call SEMICOLON { top= 0; /* Reset register stack */ }
	 | local_var
	 | compound_statement
	 | IF LPARENT expression RPARENT {
			$<my_nlabel>1=nlabelif;
			nlabelif++;

			fprintf(fasm, "\tcmpq $0, %%%s\n", regStk[top-1]);
			fprintf(fasm, "\tje else%d\n", nlabelif);
			top--;

	 	} 
		statement {
			fprintf(fasm, "\tjmp after_else%d\n", nlabelif);
			fprintf(fasm, "\telse%d:\n", nlabelif);
	 	} 
	 	else_optional{
			fprintf(fasm, "\tafter_else%d:", nlabelif);

	 	}
	 | WHILE LPARENT {
		// act 1
		$<my_nlabel>1=nlabelloops;												// allows for attaching while loop in assembly to specific token
		nlabelloops++;
		fprintf(fasm, "while_start_%d:\n", $<my_nlabel>1);
		fprintf(fasm, "please_do_continue_%d:\n", $<my_nlabel>1);				// necessary for continue statement
         }
         expression RPARENT {
		// act2
		fprintf(fasm, "\tcmpq $0, %%rbx\n");
		fprintf(fasm, "\tje while_end_%d\n", $<my_nlabel>1);
		top--;
         }
         statement {
		// act3
		fprintf(fasm, "\tjmp while_start_%d\n", $<my_nlabel>1);
		fprintf(fasm, "while_end_%d:\n", $<my_nlabel>1);
	 }
	 | DO { 
		$<my_nlabel>1=nlabelloops;
		nlabelloops++;
		fprintf(fasm, "while_start_%d:\n", $<my_nlabel>1);
		fprintf(fasm, "please_do_continue_%d:\n", $<my_nlabel>1);			// necessary for continue statement

	 }
	 statement WHILE LPARENT expression {
		fprintf(fasm, "\tcmpq $0, %%%s\n", regStk[top-1]);
		fprintf(fasm, "\tjne while_start_%d\n", $<my_nlabel>1);
		top--;

	 } 
	 RPARENT SEMICOLON {
		fprintf(fasm, "while_end_%d:\n", $<my_nlabel>1);					// necessary for break statement

	 }
	 | FOR LPARENT assignment SEMICOLON {
		$<my_nlabel>1=nlabelloops;
		nlabelloops++;
		fprintf(fasm, "while_start_%d:\n", $<my_nlabel>1);

	 } expression {

		fprintf(fasm, "\tcmpq $0, %%%s\n", regStk[top-1]);
		fprintf(fasm, "\tje while_end_%d\n", $<my_nlabel>1);
		fprintf(fasm, "\tjne stuff_in_loop%d\n", $<my_nlabel>1);
		top--;

	 }
	   SEMICOLON {
		fprintf(fasm, "for_%d:\n", $<my_nlabel>1);
		fprintf(fasm, "please_do_continue_%d:\n", $<my_nlabel>1);

	   } assignment {
		fprintf(fasm, "\tjmp while_start_%d\n", $<my_nlabel>1);

	   } RPARENT {
		fprintf(fasm, "stuff_in_loop%d:\n", $<my_nlabel>1);

	   } statement {
		fprintf(fasm, "\tjmp for_%d\n", $<my_nlabel>1);
		fprintf(fasm, "while_end_%d:\n", $<my_nlabel>1);

	   }
	 | jump_statement
	 ;

else_optional:
         ELSE  statement
	 | /* empty */
         ;

jump_statement:
         CONTINUE SEMICOLON {
			$<my_nlabel>1=nlabelloops - 1;										
			fprintf(fasm, "\t jmp please_do_continue_%d\n", $<my_nlabel>1);

		 }
	 | BREAK SEMICOLON {
		$<my_nlabel>1=nlabelloops - 1;
		fprintf(fasm, "\tjmp while_end_%d\n", $<my_nlabel>1);
	 }
	 | RETURN expression SEMICOLON {
		 fprintf(fasm, "\tmovq %%rbx, %%rax\n");
		 top = 0;

		fprintf(fasm, "# Restore registers\n");
		fprintf(fasm, "\tpopq %%r15\n");
		fprintf(fasm, "\tpopq %%r14\n");
		fprintf(fasm, "\tpopq %%r13\n");
		fprintf(fasm, "\tpopq %%r10\n");
		fprintf(fasm, "\tpopq %%rbx\n");
		fprintf(fasm, "\tpopq %%rbx\n");

		fprintf(fasm, "\taddq $256, %%rsp\n");													/*restoring space in stack*/

		fprintf(fasm, "\tleave\n");
		fprintf(fasm, "\tret\n");


	 }
	 ;

%%

void yyset_in (FILE *  in_str );

int
yyerror(const char * s)
{
	fprintf(stderr,"%s:%d: %s\n", input_file, line_number, s);
}


int
main(int argc, char **argv)
{
	printf("-------------WARNING: You need to implement global and local vars ------\n");
	printf("------------- or you may get problems with top------\n");
	
	// Make sure there are enough arguments
	if (argc <2) {
		fprintf(stderr, "Usage: simple file\n");
		exit(1);
	}

	// Get file name
	input_file = strdup(argv[1]);

	int len = strlen(input_file);
	if (len < 2 || input_file[len-2]!='.' || input_file[len-1]!='c') {
		fprintf(stderr, "Error: file extension is not .c\n");
		exit(1);
	}

	// Get assembly file name
	asm_file = strdup(input_file);
	asm_file[len-1]='s';

	// Open file to compile
	FILE * f = fopen(input_file, "r");
	if (f==NULL) {
		fprintf(stderr, "Cannot open file %s\n", input_file);
		perror("fopen");
		exit(1);
	}

	// Create assembly file
	fasm = fopen(asm_file, "w");
	if (fasm==NULL) {
		fprintf(stderr, "Cannot open file %s\n", asm_file);
		perror("fopen");
		exit(1);
	}

	// Uncomment for debugging
	//fasm = stderr;

	// Create compilation file
	// 
	yyset_in(f);
	yyparse();

	// Generate string table
	int i;
	for (i = 0; i<nstrings; i++) {
		fprintf(fasm, "string%d:\n", i);
		fprintf(fasm, "\t.string %s\n\n", string_table[i]);
	}

	fclose(f);
	fclose(fasm);

	return 0;
}


