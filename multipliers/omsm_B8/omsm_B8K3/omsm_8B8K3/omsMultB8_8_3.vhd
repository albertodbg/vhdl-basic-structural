--///////////////////////////////////////////////////////////////////////
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

--This module implements a 8x8 radix-8 omsMult with k=3;

entity omsMultB8_8_3 is
	port(
		Xs: in std_logic_vector(7 downto 0);
		Ys: in std_logic_vector(7 downto 0);
		Ts: in std_logic_vector(9 downto 0);
		Gx: in std_logic_vector(1 downto 0);
		Px: in std_logic_vector(1 downto 0);
		Gy: in std_logic_vector(1 downto 0);
		Py: in std_logic_vector(1 downto 0);
		Gt: in std_logic_vector(2 downto 0);
		Pt: in std_logic_vector(2 downto 0);
		Zs: out std_logic_vector(15 downto 0);
		Zc: out std_logic_vector(15 downto 0)
	);
end omsMultB8_8_3;

architecture estr of omsMultB8_8_3 is

	--Component declarations

	component onTheFlyCorrecterBooth8_2 is
		generic(
			N: integer;
			K: integer;
			LOG_N: integer;--Ceiling log(N)
			LOG_K: integer;--Ceiling log(K)
			LOG_N_div_K: integer--Ceiling log(N/K)
		);
		port(
			Xs: in std_logic_vector((N-1) downto 0);
			Ys: in std_logic_vector((N-1) downto 0);
			Ts: in std_logic_vector((N+1) downto 0);
			Gx: in std_logic_vector((N/K-1) downto 0);
			Px: in std_logic_vector((N/K-1) downto 0);
			Gy: in std_logic_vector((N/K-1) downto 0);
			Py: in std_logic_vector((N/K-1) downto 0);
			Gt: in std_logic_vector(((N+2)/K-1) downto 0);
			Pt: in std_logic_vector(((N+2)/K-1) downto 0);
			X: out std_logic_vector((N-1) downto 0);--X real multiplicand
			T: out std_logic_vector((N+1) downto 0);--T real multiple
			YBooth_sel: out std_logic_vector((3*(N/3)+2) downto 0);--Y Booth selection signals
			YBooth_signs: out std_logic_vector((N/3) downto 0)--Y Booth sign signals
		);
	end component;

	component mux5to1 is
		generic(
			N: integer
		);
		port(
			x0: in std_logic_vector((N-1) downto 0);
			x1: in std_logic_vector((N-1) downto 0);
			x2: in std_logic_vector((N-1) downto 0);
			x3: in std_logic_vector((N-1) downto 0);
			x4: in std_logic_vector((N-1) downto 0);
			ctrl: in std_logic_vector(2 downto 0);
			z: out std_logic_vector((N-1) downto 0)
		);
	end component;

	component kogge_stone is
		generic(
			N: integer;
			S: integer --Number of stages=log(N)
		);
			port(
			a: in std_logic_vector((N-1) downto 0);
			b: in std_logic_vector((N-1) downto 0);
			cin: in std_logic;
			z: out std_logic_vector((N-1) downto 0);
			cout: out std_logic
		);
	end component;

	component compr4to2Tree_4_16 is
		port(
			x0: in std_logic_vector(15 downto 0);
			x1: in std_logic_vector(15 downto 0);
			x2: in std_logic_vector(15 downto 0);
			x3: in std_logic_vector(15 downto 0);
			s: out std_logic_vector(15 downto 0);
			c: out std_logic_vector(15 downto 0)
		);
	end component;

	--Type declarations

	type ppMatrix is array (0 to 2) of std_logic_vector(9 downto 0);--8+2
	type ppMatrix2 is array (0 to 3) of std_logic_vector(15 downto 0);--Math.ceil((8+1)/3)

	--Signal declarations

	signal X: std_logic_vector(7 downto 0);
	signal zero10: std_logic_vector(9 downto 0);
	signal x1: std_logic_vector(9 downto 0);
	signal doublex1: std_logic_vector(9 downto 0);
	signal threex1: std_logic_vector(9 downto 0);
	signal quadx1: std_logic_vector(9 downto 0);
	signal cin_thr: std_logic;
	signal cout_thr: std_logic;
	signal sel: std_logic_vector(8 downto 0);
	signal signs: std_logic_vector(2 downto 0);
	signal ext_signs: std_logic_vector(2 downto 0);--For negative multipliers
	signal pp: ppMatrix;
	signal ppAux: ppMatrix;
	signal ppSign: ppMatrix;
	signal pp2: ppMatrix2;
	signal cout: std_logic;
	signal s1: std_logic_vector(15 downto 0);
	signal c1: std_logic_vector(15 downto 0);

	signal T: std_logic_vector(9 downto 0);

begin

	--Booth encoding, given by the on-the-fly correcter
	otf_corr: onTheFlyCorrecterBooth8_2 generic map(8,3,3,2,1)
		port map(Xs,Ys,Ts,Gx,Px,Gy,Py,Gt,Pt,X,T,sel,signs);

	--X mantissas
	zero10 <= (OTHERS => '0');
	x1 <= X(7) & X(7) & X;--In order to make doublex1 >=0 and minusDoublex1 <0
	doublex1 <= x1(8 downto 0) & '0';
	quadx1 <= X & "00";

	threex1 <= T;

	--Mux5to1
	muxGen:
	for i in 0 to 2 generate
		muxStage: mux5to1 generic map(10)
			port map(zero10,x1,doublex1,threex1,quadx1,sel((3*i+2) downto (3*i)),ppAux(i));
		ppSign(i) <= (OTHERS => signs(i));
		pp(i) <= ppAux(i) xor ppSign(i);
		ext_signs(i) <= ((signs(i) xnor X(7)) and 
			not(not(sel(3*i+2)) and not(sel(3*i+1)) and not(sel(3*i)) and signs(i))) or 
			(not(sel(3*i+2)) and not(sel(3*i+1)) and not(sel(3*i)) and not(signs(i)));
	end generate muxGen;

	--Complete partial products
	pp2(0)(15 downto 14) <= (OTHERS => '0');
	pp2(0)(13 downto 0) <= ext_signs(0) & not(ext_signs(0)) & not(ext_signs(0)) & not(ext_signs(0)) & pp(0);
	complGen:
	for i in 1 to 2 generate
		ifGenlt1:
		if (i<1) generate
		--MS '0's
		pp2(i)(15 downto (10 + 3*i + 3)) <= (OTHERS => '0');
		--Hot 1's
			pp2(i)(10 + 3*i + 2) <= '1';
		end generate ifGenlt1;
		--not(signs)
		ifGenlt2:
		if (i<2) generate
			pp2(i)((10 + 3*i + 1) downto (10 + 3*i)) <= '1' & ext_signs(i);
			--Copy operand
			pp2(i)((10 + 3*i - 1) downto (3*i)) <= pp(i);
		end generate ifGenlt2;
		ifGeneq2:
		if (i=2) generate
			--i=2 ==> overflow
			--Copy operand
			pp2(i)((10 + 3*i-2) downto (3*i)) <= pp(i)(8 downto 0);
		end generate ifGeneq2;
		--'0' and signs
		pp2(i)((3*i-1) downto (3*i-3)) <= "00" & signs(i-1);
		--LS '0's
		ifGengt1:
		if (i>1) generate
			pp2(i)((3*i-4) downto 0) <= (OTHERS => '0');
		end generate ifGengt1;
	end generate complGen;

	--Completing antepenultimate and penultimate rows
	pp2(1)(15) <= '1';--Hot one
	pp2(2)(15) <= pp(2)(9);--pp last bit

	pp2(3) <= "000000000" & signs(2) & "000000";

	--[4:2] tree
	tree: compr4to2Tree_4_16 port map(pp2(0),pp2(1),pp2(2),pp2(3),s1,c1);

	Zs <= s1;
	Zc <= c1;--Beware: carry must be shifted one position to the left

end estr;
