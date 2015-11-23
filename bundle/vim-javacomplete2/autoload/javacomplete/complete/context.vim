let g:JC__CONTEXT_AFTER_DOT		        = 1
let g:JC__CONTEXT_METHOD_PARAM	        = 2
let g:JC__CONTEXT_IMPORT		        = 3
let g:JC__CONTEXT_IMPORT_STATIC	        = 4
let g:JC__CONTEXT_PACKAGE_DECL	        = 6 
let g:JC__CONTEXT_NEED_TYPE		        = 7 
let g:JC__CONTEXT_COMPLETE_CLASS	    = 8
let g:JC__CONTEXT_METHOD_REFERENCE      = 9
let g:JC__CONTEXT_ANNOTATION_FIELDS     = 10
let g:JC__CONTEXT_COMPLETE_ON_OVERRIDE  = 11
let g:JC__CONTEXT_OTHER 		        = 0

function! javacomplete#complete#context#FindContext()
  let statement = javacomplete#scanner#GetStatement()

  let start = col('.') - 1

  if javacomplete#util#GetClassNameWithScope() =~ '^[@A-Z]\([A-Za-z0-9_]*\|\)$'
    let b:context_type = g:JC__CONTEXT_COMPLETE_CLASS

    let curline = getline(".")
    let start = col('.') - 1

    while start > 0 && curline[start - 1] =~ '[@A-Za-z0-9_]'
      let start -= 1
      if curline[start] == '@'
        break
      endif
    endwhile

    return start
  elseif statement =~ '[.0-9A-Za-z_]\s*$'
    let valid = 1
    if statement =~ '\.\s*$'
      let valid = statement =~ '[")0-9A-Za-z_\]]\s*\.\s*$' && statement !~ '\<\H\w\+\.\s*$' && statement !~ '\C\<\(abstract\|assert\|break\|case\|catch\|const\|continue\|default\|do\|else\|enum\|extends\|final\|finally\|for\|goto\|if\|implements\|import\|instanceof\|interface\|native\|new\|package\|private\|protected\|public\|return\|static\|strictfp\|switch\|synchronized\|throw\|throws\|transient\|try\|volatile\|while\|true\|false\|null\)\.\s*$'
    endif
    if !valid
      return -1
    endif

    let b:context_type = g:JC__CONTEXT_AFTER_DOT

    " import or package declaration
    if statement =~# '^\s*\(import\|package\)\s\+'
      let statement = substitute(statement, '\s\+\.', '.', 'g')
      let statement = substitute(statement, '\.\s\+', '.', 'g')
      if statement =~ '^\s*import\s\+'
        let b:context_type = statement =~# '\<static\s\+' ? g:JC__CONTEXT_IMPORT_STATIC : g:JC__CONTEXT_IMPORT
        let b:dotexpr = substitute(statement, '^\s*import\s\+\(static\s\+\)\?', '', '')
      else
        let b:context_type = g:JC__CONTEXT_PACKAGE_DECL
        let b:dotexpr = substitute(statement, '\s*package\s\+', '', '')
      endif

      " String literal
    elseif statement =~  '"\s*\.\s*$'
      let b:dotexpr = substitute(statement, '\s*\.\s*$', '\.', '')
      return start - strlen(b:incomplete)

    elseif &ft == 'jsp' && statement =~# '.*page.*import.*'
      let b:context_type = g:JC__CONTEXT_IMPORT
      let b:dotexpr = javacomplete#scanner#ExtractCleanExpr(statement)
    elseif matchend(statement, '^\s*' . g:RE_TYPE_DECL) != -1
      " type declaration
      
      let b:dotexpr = strpart(statement, idx_type)
      " return if not after extends or implements
      if b:dotexpr !~ '^\(extends\|implements\)\s\+'
        return -1
      endif
      let b:context_type = g:JC__CONTEXT_NEED_TYPE
    else
      let stat = javacomplete#util#Trim(statement)
      if matchend(stat, '.*@Override$') >= 0
        let b:context_type = g:JC__CONTEXT_COMPLETE_ON_OVERRIDE
      endif
    endif

    let b:dotexpr = javacomplete#scanner#ExtractCleanExpr(statement)
    if b:dotexpr =~ '.*::.*'
      let b:context_type = g:JC__CONTEXT_METHOD_REFERENCE
      let b:incomplete = strpart(b:dotexpr, stridx(b:dotexpr, ':') + 2)
      let b:dotexpr = strpart(b:dotexpr, 0, strridx(b:dotexpr, ':') + 1)
      return start - strlen(b:incomplete)
    endif

    " all cases: " java.ut|" or " java.util.|" or "ja|"
    let b:incomplete = strpart(b:dotexpr, strridx(b:dotexpr, '.')+1)
    let b:dotexpr = strpart(b:dotexpr, 0, strridx(b:dotexpr, '.')+1)
    return start - strlen(b:incomplete)

  elseif statement =~ '^@'. g:RE_IDENTIFIER
    let b:context_type = g:JC__CONTEXT_ANNOTATION_FIELDS
    let b:incomplete = substitute(statement, '\s*(\s*$', '', '')

    return start

    " method parameters, treat methodname or 'new' as an incomplete word
  elseif statement =~ '(\s*$'
    " TODO: Need to exclude method declaration?
    let b:context_type = g:JC__CONTEXT_METHOD_PARAM
    let pos = strridx(statement, '(')
    let s:padding = strpart(statement, pos+1)
    let start = start - (len(statement) - pos)

    let statement = substitute(statement, '\s*(\s*$', '', '')

    " new ClassName?
    let str = matchstr(statement, '\<new\s\+' . g:RE_QUALID . '$')
    if str != ''
      let str = substitute(str, '^new\s\+', '', '')
      if !s:IsKeyword(str)
        let b:incomplete = '+'
        let b:dotexpr = str
        return start - len(b:dotexpr)
      endif

      " normal method invocations
    else
      let pos = match(statement, '\s*' . g:RE_IDENTIFIER . '$')
      " case: "method(|)", "this(|)", "super(|)"
      if pos == 0
        let statement = substitute(statement, '^\s*', '', '')
        " treat "this" or "super" as a type name.
        if statement == 'this' || statement == 'super' 
          let b:dotexpr = statement
          let b:incomplete = '+'
          return start - len(b:dotexpr)

        elseif !s:IsKeyword(statement)
          let b:incomplete = statement
          return start - strlen(b:incomplete)
        endif

        " case: "expr.method(|)"
      elseif statement[pos-1] == '.' && !s:IsKeyword(strpart(statement, pos))
        let b:dotexpr = javacomplete#scanner#ExtractCleanExpr(strpart(statement, 0, pos))
        let b:incomplete = strpart(statement, pos)
        return start - strlen(b:incomplete)
      endif
    endif

  elseif statement =~ '[.0-9A-Za-z_\<\>]*::$'
    let b:context_type = g:JC__CONTEXT_METHOD_REFERENCE
    let b:dotexpr = javacomplete#scanner#ExtractCleanExpr(statement)
    return start - strlen(b:incomplete)
  endif

  return -1
endfunction

function! javacomplete#complete#context#ExecuteContext(base)
  let result = []

  call javacomplete#logger#Log("Context: ". b:context_type)
  if len(b:incomplete) > 0
    call javacomplete#logger#Log("Incomplete: ". b:incomplete)
  endif
  if len(b:dotexpr) > 0
    call javacomplete#logger#Log("DotExpr: ". b:dotexpr)
  endif
  
  " Try to complete incomplete class name
  if b:context_type == g:JC__CONTEXT_COMPLETE_CLASS && a:base =~ '^[@A-Z]\([A-Za-z0-9_]*\|\)$'
    let result = javacomplete#complete#complete#CompleteSimilarClasses(a:base)
  elseif b:context_type == g:JC__CONTEXT_COMPLETE_ON_OVERRIDE
    let result = javacomplete#complete#complete#CompleteAfterOverride()
  endif

  if !empty(result)
    return result
  endif

  if b:dotexpr !~ '^\s*$'
    if b:context_type == g:JC__CONTEXT_AFTER_DOT || b:context_type == g:JC__CONTEXT_METHOD_REFERENCE
      let result = javacomplete#complete#complete#CompleteAfterDot(b:dotexpr)
    elseif b:context_type == g:JC__CONTEXT_IMPORT || b:context_type == g:JC__CONTEXT_IMPORT_STATIC || b:context_type == g:JC__CONTEXT_PACKAGE_DECL || b:context_type == g:JC__CONTEXT_NEED_TYPE
      let result = javacomplete#complete#complete#GetMembers(b:dotexpr[:-2])
    elseif b:context_type == g:JC__CONTEXT_METHOD_PARAM
      if b:incomplete == '+'
        let result = javacomplete#complete#complete#GetConstructorList(b:dotexpr)
      else
        let result = javacomplete#complete#complete#CompleteAfterDot(b:dotexpr)
      endif
    endif

    " only incomplete word
  elseif b:incomplete !~ '^\s*$'
    " only need methods
    if b:context_type == g:JC__CONTEXT_METHOD_PARAM
      let methods = javacomplete#complete#complete#SearchForName(b:incomplete, 0, 1)[1]
      call extend(result, eval('[' . javacomplete#complete#complete#DoGetMethodList(methods, 0) . ']'))
    elseif b:context_type == g:JC__CONTEXT_ANNOTATION_FIELDS
      let result = javacomplete#complete#complete#CompleteAnnotationsParameters(b:incomplete)
    else
      let result = javacomplete#complete#complete#CompleteAfterWord(b:incomplete)
    endif

    " then no filter needed
    let b:incomplete = ''
  endif

  return result
endfunction

" vim:set fdm=marker sw=2 nowrap:
