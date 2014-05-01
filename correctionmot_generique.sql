-- Function: correctionmot_generique(text, character varying, integer[], integer)

-- DROP FUNCTION correctionmot_generique(text, character varying, integer[], integer);

CREATE OR REPLACE FUNCTION correctionmot_generique(IN in_phrase text, IN in_table character varying, IN ref integer[], IN nbsuggest integer)
  RETURNS TABLE(outmot character varying, outids integer[], tri integer, dia text) AS
$BODY$
DECLARE
	recRetour record;
	strSql character varying;
	goodMatch boolean;
	perfectMatch boolean;
	i integer;
BEGIN 
	goodMatch = false;
	perfectMatch = false;
i=0;
	IF ARRAY[-1] && ref THEN 
	
		FOR recRetour IN EXECUTE
			concat ('SELECT sousReq.mot, sousReq.outids, row_number()  over (ORDER BY tri1) AS tri,sousReq.tri1,sousReq.perfect, sousReq.diacritique  
				FROM (SELECT  a.mot::character varying AS mot, a.ids  AS outids ,
						CASE WHEN (a.diacritique <-> array_to_string( ts_lexize(''french_stem'',unaccent(',quote_literal(in_phrase),')),''$'')) = 0 THEN 1
						ELSE 2 END AS tri1,
						CASE WHEN (a.mot <-> unaccent(',quote_literal(in_phrase),')) = 0 THEN 1
						ELSE 2 END AS perfect,
						a.diacritique
					FROM ',in_table,'_dict a 
					WHERE a.diacritique <-> array_to_string( ts_lexize(''french_stem'',unaccent(',quote_literal(in_phrase),')),''$'')  < 1  -- il serait bon 
					ORDER BY a.diacritique <-> array_to_string( ts_lexize(''french_stem'',unaccent(',quote_literal(in_phrase),')),''$'') --Tri par indice de similarité
					LIMIT ',nbSuggest,' ) as sousReq 
				ORDER BY tri1,perfect')
		LOOP
			i=i+1;
			IF recRetour.tri1 = 1 AND goodMatch is false THEN 
				goodMatch = true; 
				IF recRetour.perfect=1 THEN 
					perfectMatch = true;
					RETURN QUERY SELECT recRetour.mot, recRetour.outids, recRetour.tri::integer ,recRetour.diacritique;
				END IF;
			END IF;

			IF (recRetour.tri1=1 OR goodMatch is false) AND  perfectMatch IS false  THEN
				RETURN QUERY SELECT recRetour.mot, recRetour.outids, recRetour.tri::integer, recRetour.diacritique;
			END IF;
		END LOOP;
	ELSE 
	 
		FOR recRetour IN EXECUTE
			concat('SELECT sousReq.mot, sousReq.outids, row_number()  over (ORDER BY tri1,tri2) AS tri,sousReq.tri1,sousReq.perfect,sousReq.diacritique    
				FROM (	SELECT  a.mot::character varying AS mot,   a.ids    AS outids , 
						CASE WHEN a.ids && ARRAY[',array_to_string(ref,','),'] = true THEN 1 ELSE 2 END AS tri2,
						CASE WHEN a.diacritique <-> array_to_string( ts_lexize(''french_stem'',unaccent(',quote_literal(in_phrase),')),''$'') = 0 THEN 1
						ELSE 2 END AS tri1,
						CASE WHEN (a.diacritique <-> array_to_string( ts_lexize(''french_stem'',unaccent(',quote_literal(in_phrase),')),''$'')) = 0 THEN 1
						ELSE 2 END AS perfect,
						a.diacritique
					FROM ',in_table,'_dict a 
					WHERE /*Clause where en mots clairs: la première partie du where limite a la suggestion de mots qui ne sont pas bien orthographié et qui 
						ont un lien avec les autres mots de la phrase OU que le mot est bien orthographié.*/
						(a.diacritique <-> array_to_string( ts_lexize(''french_stem'',unaccent(',quote_literal(in_phrase),')),''$'')  < 1  -- il serait bon 
						AND  a.ids && ARRAY[',array_to_string(ref,','),'] = true ) OR (a.diacritique <-> array_to_string( ts_lexize(''french_stem'',unaccent(',quote_literal(in_phrase),')),''$'')  = 0 )
					ORDER BY a.diacritique <-> array_to_string( ts_lexize(''french_stem'',unaccent(',quote_literal(in_phrase),')),''$'') --Tri par indice de similarité
					LIMIT ',nbSuggest,' )as sousReq 
				ORDER BY tri1,perfect')
		LOOP
			i=i+1;
			IF recRetour.tri1 = 1 AND goodMatch is false THEN 
				goodMatch = true; 
				IF recRetour.perfect=1 THEN 
					perfectMatch  = true;
					RETURN QUERY SELECT recRetour.mot, recRetour.outids, recRetour.tri::integer ,recRetour.diacritique;
				END IF;
			END IF;

			IF (recRetour.tri1=1 OR goodMatch is false) AND  perfectMatch IS false  THEN
				RETURN QUERY SELECT recRetour.mot, recRetour.outids, recRetour.tri::integer ,recRetour.diacritique;
			END IF;
		END LOOP;
	END IF;

IF i=0 THEN RETURN QUERY SELECT in_phrase::character varying, ARRAY[-1], 1 ,in_phrase; END IF;
	 
END;

$BODY$
  LANGUAGE plpgsql VOLATILE STRICT
  COST 100
  ROWS 1000;
ALTER FUNCTION correctionmot_generique(text, character varying, integer[], integer)
  OWNER TO cyrs03;
