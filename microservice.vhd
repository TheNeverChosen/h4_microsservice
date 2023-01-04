-- ############################################################################
-- @copyright   Miguel Grimm <miguelgrimm@gmail>
--
-- @brief       Função do microsserviço limpa, carga e conta.
--
-- @file        rlc_microservice.vhd
-- @version     1.0
-- @date        27 Julho 2021
--
-- @section     HARDWARES & SOFTWARES.
--              +compiler     Quartus Web Edition versão 13 sp 1.
--                            Quartus Primer Lite Edition Versão 18.
--              +revisions    Versão (data): Descrição breve.
--                            ++ 1.0 (27 Julho 2020): Versão inicial.
--
-- @section     AUTHORS & DEVELOPERS.
--              +institution  UFAM - Universidade Federal do Amazonas.
--              +courses      Engenharia da Computação / Engenharia Elétrica.
--              +teacher      Miguel Grimm <miguelgrimm@gmail.com>
--
--                            Compilação e Simulação:
-- 	            +student      Kevin Guimarães <kevin.guimaraes37@gmail.com> 
--
-- @section     LICENSE
--
--              GNU General Public License (GNU GPL).
--
--              Este programa é um software livre; Você pode redistribuí-lo
--              e/ou modificá-lo de acordo com os termos do "GNU General Public
--              License" como publicado pela Free Software Foundation; Seja a
--              versão 3 da licença, ou qualquer outra versão posterior.
--
--              Este programa é distribuído na esperança de que seja útil,
--              mas SEM QUALQUER GARANTIA; Sem a garantia implícita de
--              COMERCIALIZAÇÃO OU USO PARA UM DETERMINADO PROPÓSITO.
--              Veja o site da "GNU General Public License" para mais detalhes.
--
-- @htmlonly    http://www.gnu.org/copyleft/gpl.html
--
-- @section     REFERENCES.
--              + CHU, Pong P. RTL Hardware Design Using VHDL. 2006. 669 p.
--              + AMORE, Robert d'. VHDL - Descrição e Síntese de Circuitos
--                Digitais. 2. ed. Rio de Janeiro : LTC, 2012. 292 p.
--              + PEDRONI, Volnei A. Eletrônica Digital Moderna e VHDL.
--                Rio de Janeiro : Elsevier, 2010. 619 p.
--              + TOCCI, Ronald J., WIDNER, Neal S. & MOSS, Gregory.
--                Sistemas Digitais - Princípios e Aplicações, 12. ed.
--                São Paulo : Person Education do Brasil, 2018. 1034 p.
--
-- ############################################################################

library ieee;
use ieee.numeric_bit.all;
USE ieee.std_logic_1164.all; 
use work.dsf_std.all;


-- ----------------------------------------------------------------------------
-- @brief      Geração do microsserviço limpa, carrega e conta.
--
-- @param[in]  enable  -  1, habilita todas as operações da função e
--                        0, desabilita a função.
--
--             areset  -  1, coloca o microsserviço no estado inicial e
--                        0, nenhuma operação.
--
--             start   -  0 => 1 => 0, dá a partida do início das operações e
--                        caso contrário, não tem nenhum efeito.
--
--             clk     -  sinal de sincronismo, ativo na transição de descida.
--
-- @param[out] reset_o -  1, operação limpa ativada e
--                        0, nenhuma operação.
--
--             load_o  -  1, operação carga ativada e
--                        0, nenhuma operação.
--
--             count_o -  1, operação de contagem ativada e
--                        0, nenhuma operação.
--
--             state   -  0, estado corrente wait4start_s,
--                        1, estado corrente reset_s,
--                        2, estado corrente load_s,
--                        3, estado corrente count_s e
--                        4, estado de sinalização de erro.
-- ----------------------------------------------------------------------------
entity microsservice is

  port (
    -- INPUT
	 clk                 : IN bit; -- microsservice clock
	 reset_in            : IN bit; -- reset signal
	 enable_in           : IN bit; -- enable signal
	 floor_req_active_in : IN bit; -- active signal by floor request
	 floor_req_in        : IN integer range 3 DOWNTO 1; -- floor requested
	 floor_cur_in        : IN integer range 3 DOWNTO 1; -- current floor
	 door_state_in       : IN integer range 4 DOWNTO 0; -- state of door

	 -- OUTPUT
	 enable_out        : OUT bit;
	 reset_out 	       : OUT bit;
	 door_start_out    : OUT bit;
	 door_mode_out     : OUT bit;
	 cabin_code_out    : OUT integer range 4 DOWNTO 0;
	 cabin_start_out   : OUT bit;
	 cabin_floor_out   : OUT bit
	 display_floor_out : OUT integer range 3 DOWNTO 1;
	 display_move_out	 : OUT bit_vector (1 DOWNTO 0)
  );
  
end microsservice;



architecture microsservice_a of microsservice is

  -- --------------------------------------------------------------------------
  -- @detail           CONSTANTES E TIPOS GLOBAIS DA ARQUITETURA             --
  -- --------------------------------------------------------------------------

  -- Limite de estados do microsserviço.
  --  constant  MAX_STATE  :  integer  :=  state'high;

  -- Estados do microsserviço.
  type  state_t is (wait4req_s,        -- 0, Espera solicitação de andar
                    reg_floor_s,       -- 1, Tratamento inicial de requisição (data_reg)
						  close_door_beg_s,  -- 2, Fechamento de porta pré-movimentação
						  move_to_floor_s,   -- 3, Movimentação do Elevador para o andar solicitado
						  open_door_s,       -- 4, Abertura da porta ao chegar no andar
						  wait4time_s,       -- 5, Espera 
						  close_door_end_s,
						  reset_s,      
						  noise_s);
						  
  type  action_t is (closed_act,
							opening_act,
							opened_act,
							closing_act,
							noise_act);
  
  -- --------------------------------------------------------------------------
  -- @detail                FUNÇÕES GLOBAIS DA ARQUITETURA                   --
  -- --------------------------------------------------------------------------

  function next_state (reset : STD_LOGIC; signal clk : bit; pulse : STD_LOGIC;
                       state : state_t) return state_t is

    -- Próximo estado da máquina: modo memória.
	 variable  nx_state    :  state_t  :=  state;

  begin

   if (reset = '1') then
      -- Modo reset.
	   nx_state := reset_s;

	elsif high2low(clk) then
	  
      -- Encontra o próximo estado.
      case state is

		when reset_s      =>   -- Modo conta.
                           nx_state := wait4pulse_s;
		
	   when wait4pulse_s => -- Modo espera o início da partida.
                         if (pulse = '1') then
                           -- Modo partindo.
	                        nx_state := set3_s;
                         end if;
	   
      when set3_s       => -- Modo seta contador 3s
		                   nx_state := count3_s;
		
		when count3_s     => -- Modo contagem contador 3s
		                   if (q3 = "0000") then
		                     nx_state := set9_s;
								 end if;

	   when set9_s       => -- Modo seta contador 9s
		                   nx_state := count9_s;
		
      when count9_s     => -- Modo contagem contador 9s
		                   if(q9 = "0000") then
		                     nx_state := wait4pulse_s;
								 end if;

	   when noise_s      =>   -- Modo reinício automático.
                         nx_state := reset_s;

      when others       =>   -- Estado de erro devido a ruído.
		                   nx_state := noise_s;

      end case;

    end if;  -- reset & clk.

	return nx_state;

  end next_state;
  
  function get_out (reset : STD_LOGIC; target, current : state_t) return STD_LOGIC is
   -- Próxima saída: modo memória.
	variable  nx_out  :  STD_LOGIC;
  begin
    if (reset = '1') then
      -- Modo limpa.
      nx_out := '0';	  
    else
      if (current = target) then
        -- Modo ativado.
        nx_out := '1';
      else
        -- Modo desativado.
        nx_out := '0';
      end if;
    end if;

    return nx_out;
  end get_out;
  
  function get_led(reset : STD_LOGIC; color : color_t; current : state_t) return STD_LOGIC is
    variable nx_led  :  STD_LOGIC;
	begin
		if(reset = '1')
			then nx_led := '0';
			
		else
			if(color = green_c) then
				if(current = set9_s or current = count9_s) then nx_led := '1';
				else nx_led := '0';
				end if;
			else
				if(current = reset_s or current = count9_s or current = set9_s) then nx_led := '0';
				else nx_led := '1';
				end if;
			end if;
		end if;
		return nx_led;
	end get_led;

  -- --------------------------------------------------------------------------
  -- @detail                BUFFERS LOCAIS DA ARQUITETURA                    --
  -- --------------------------------------------------------------------------

  -- Estado simbólico do microsserviço.
  signal   current   :   state_t   :=   reset_s;

begin

  -- OP1. Próximo estado.
  current <= next_state(reset_in, clk, pulse, q3, q9, current) when (enable_in = '1');
	 
  enable_out <= enable_in;
  reset_out <= get_out(reset_in, reset_s, current) when (enable_in = '1');
  
  set3 <= get_out(reset_in, set3_s, current) when (enable_in = '1');
  count3 <= get_out(reset_in, count3_s, current) when (enable_in = '1');

  set9 <= get_out(reset_in, set9_s, current) when (enable_in = '1');
  count9 <= get_out(reset_in, count9_s, current) when (enable_in = '1');
  
  led_red <= get_led(reset_in, red_c, current) when (enable_in='1');
  led_green <= get_led(reset_in, green_c, current) when (enable_in='1');	

end microsservice_a;








